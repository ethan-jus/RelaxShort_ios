import Foundation

// MARK: - Real Member Repository

/// 真实 Member 订阅页数据仓库。
/// 调用 `GET /api/v2/member`，不依赖 Mock 数据。
struct RealMemberRepository: MemberRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchMemberContent(
        contentLanguage: String?,
        countryCode: String?
    ) async throws -> MemberContent {
        let dto: MemberResponseDTO = try await client.requestData(
            .member(
                contentLanguage: contentLanguage,
                countryCode: countryCode
            )
        )
        return Self.map(dto: dto)
    }

    static func map(dto: MemberResponseDTO) -> MemberContent {
        let plans = (dto.plans ?? [])
            .compactMap { plan -> MemberPlanDisplayOption? in
                guard let productID = ProductID(rawValue: plan.storeProductId),
                      productID.isVIPSubscription else {
                    return nil
                }
                let promotion = plan.promotion.flatMap { promotion -> MemberPromotion? in
                    guard let offerType = MemberPromotionOfferType(
                        rawValue: promotion.offerType
                    ),
                    let paymentMode = MemberPromotionPaymentMode(
                        rawValue: promotion.paymentMode
                    ),
                    let periodUnit = MemberPromotionPeriodUnit(
                        rawValue: promotion.periodUnit
                    ) else {
                        return nil
                    }
                    return MemberPromotion(
                        campaignCode: promotion.campaignCode,
                        offerType: offerType,
                        paymentMode: paymentMode,
                        periodUnit: periodUnit,
                        periodValue: promotion.periodValue,
                        periodCount: promotion.periodCount,
                        badgeKey: promotion.badgeKey,
                        titleKey: promotion.titleKey,
                        startsAt: Date(
                            timeIntervalSince1970:
                                promotion.startsAtEpochSeconds
                        ),
                        endsAt: Date(
                            timeIntervalSince1970:
                                promotion.endsAtEpochSeconds
                        )
                    )
                }
                return MemberPlanDisplayOption(
                    id: plan.productCode,
                    productID: productID,
                    titleKey: plan.titleKey,
                    detailKey: plan.detailKey,
                    promotion: promotion
                )
            }

        let benefits = (dto.benefits ?? []).map {
            MemberBenefitDisplayItem(
                id: $0.code,
                icon: $0.icon ?? "checkmark.seal",
                titleKey: $0.titleKey,
                detailKey: $0.detailKey
            )
        }

        let legalLinks = dto.legalLinks.flatMap { links -> MemberLegalLinks? in
            guard let termsURL = URL(string: links.termsUrl),
                  let privacyURL = URL(string: links.privacyUrl),
                  termsURL.scheme == "https",
                  privacyURL.scheme == "https" else {
                return nil
            }
            return MemberLegalLinks(
                termsURL: termsURL,
                privacyURL: privacyURL
            )
        }

        return MemberContent(
            backgroundPosters: dto.backgroundPosters.map(FeedCardDTOMapper.toDramaItem),
            memberOnlyDramas: dto.memberOnlyDramas.map(FeedCardDTOMapper.toDramaItem),
            plans: plans,
            benefits: benefits,
            legalLinks: legalLinks
        )
    }
}
