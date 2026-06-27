import SwiftUI
import UIKit

// MARK: - Layout Constants
private let hGap: CGFloat = 10
private let vGap: CGFloat = 14
private let margin: CGFloat = 8

// MARK: - RoundedCorner
struct RoundedCorner: Shape {
    var radius: CGFloat = 4; var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path { Path(UIBezierPath(roundedRect:rect,byRoundingCorners:corners,cornerRadii:CGSize(width:radius,height:radius)).cgPath) }
}

// MARK: - Helpers
private func rankText(rank: Int) -> String? {
    guard rank <= 10 else { return nil }
    let o = rank == 1 ? "1st" : rank == 2 ? "2nd" : rank == 3 ? "3rd" : "\(rank)th"
    return rank % 2 == 1 ? "\(o) in Most Popular" : "\(o) in Top Searched"
}

// MARK: - Category Themes
struct CategoryTheme { let name: String; let bg: Color; let subBg: Color }
let categoryThemes: [CategoryTheme] = [
    CategoryTheme(name:"Counterattack",     bg:Color(red:0.35,green:0.15,blue:0.55),subBg:Color(red:0.45,green:0.25,blue:0.65)),
    CategoryTheme(name:"Forbidden Love",    bg:Color(red:0.55,green:0.10,blue:0.20),subBg:Color(red:0.65,green:0.20,blue:0.30)),
    CategoryTheme(name:"Young Adult",       bg:Color(red:0.08,green:0.35,blue:0.38),subBg:Color(red:0.12,green:0.45,blue:0.48)),
    CategoryTheme(name:"Billionaire's Game",bg:Color(red:0.45,green:0.30,blue:0.08),subBg:Color(red:0.55,green:0.40,blue:0.14)),
    CategoryTheme(name:"Fantasy Realm",     bg:Color(red:0.18,green:0.15,blue:0.45),subBg:Color(red:0.25,green:0.22,blue:0.55)),
]

// MARK: - Marketing Grid (3×3)
struct MarketingGrid: View {
    let dramas: [DramaItem]; @Binding var playerDrama: DramaItem?; let containerW: CGFloat
    private var colW: CGFloat { (containerW - margin*2 - hGap*2) / 3 }
    private var coverH: CGFloat { colW * 4 / 3 }; private var cardH: CGFloat { coverH + 48 }
    var body: some View {
        let cols = [GridItem(.fixed(colW),spacing:hGap),GridItem(.fixed(colW),spacing:hGap),GridItem(.fixed(colW),spacing:hGap)]
        LazyVGrid(columns:cols,spacing:vGap){ForEach(dramas){d in MarketingCard(drama:d,colW:colW,coverH:coverH,cardH:cardH,playerDrama:$playerDrama)}}.padding(.horizontal,margin)
    }
}
struct MarketingCard: View {
    let drama: DramaItem; let colW:CGFloat; let coverH:CGFloat; let cardH:CGFloat; @Binding var playerDrama:DramaItem?
    var body: some View {
        Button{playerDrama=drama}label:{
            VStack(alignment:.leading,spacing:0){
                ZStack(alignment: .topTrailing) {
                    CoverImageView(url: drama.coverURL, cornerRadius: DB.posterRadius, width: colW, height: coverH)
                    if let badge = drama.placementBadge {
                        HomeCardBadgeView(badge: badge)
                    }
                }
                    .frame(width:colW,height:coverH)
                Text(drama.title).font(.system(size:14,weight:.medium)).foregroundColor(DT.Color.textPrimary).lineLimit(2)
                    .padding(.horizontal,4).padding(.top,6).padding(.bottom,6).frame(maxWidth:colW,alignment:.leading)
            }.frame(width:colW,height:cardH,alignment:.top)
        }.buttonStyle(.plain)
    }
}

// MARK: - You Might Like Section (行式错位: 左Cat行 1,4,19,25… 右Cat行 11,16,22,28…)
struct YouMightLikeSection: View {
    let dramas: [DramaItem]; @Binding var playerDrama: DramaItem?; let containerW: CGFloat
    private var colW:CGFloat{(containerW-margin*2-hGap)/2}; private var coverH:CGFloat{colW*4/3}

    var body: some View {
        VStack(alignment:.leading,spacing:12){
            Text("You Might Like").font(.system(size:16,weight:.bold)).foregroundColor(DT.Color.textPrimary).padding(.horizontal,margin)
            twoColumnLayout
        }
    }

    private enum Slot{case cat(Int,[DramaItem]);case drama(DramaItem,Int)}
    private func isLCat(_ r: Int) -> Bool { if r == 1 || r == 4 || r == 19 { return true }; if r < 26 { return false }; return (r - 26) % 7 == 0 }
    private func isRCat(_ r: Int) -> Bool { if r == 11 || r == 16 { return true }; if r < 23 { return false }; return (r - 23) % 7 == 0 }

    private var twoColumnLayout: some View {
        var li:[Slot]=[]; var ri:[Slot]=[]; var ti=0; let pool=Array(dramas); var po=0
        let sorted=dramas.sorted{$0.viewCount>$1.viewCount}
        var di=0; var row=1
        while di<dramas.count {
            if isLCat(row){let s=po%pool.count;li.append(.cat(ti,(0..<4).compactMap{pool[(s+$0)%pool.count]}));ti+=1;po+=4}
            else{let d=dramas[di];di+=1;let rk=(sorted.firstIndex{$0.id==d.id} ?? -1)+1;li.append(.drama(d,rk))}
            _ = di<dramas.count || isRCat(row)
            if isRCat(row){let s=po%pool.count;ri.append(.cat(ti,(0..<4).compactMap{pool[(s+$0)%pool.count]}));ti+=1;po+=4}
            else if di<dramas.count{let d=dramas[di];di+=1;let rk=(sorted.firstIndex{$0.id==d.id} ?? -1)+1;ri.append(.drama(d,rk))}
            row+=1
        }
        return HStack(alignment:.top,spacing:hGap){
            VStack(spacing:vGap){ForEach(Array(li.enumerated()),id:\.offset){s in
                if case .cat(let ti,let sd)=s.element{CategoryCard(theme:categoryThemes[ti%categoryThemes.count],dramas:sd,colW:colW,playerDrama:$playerDrama)}
                else if case .drama(let d,let rk)=s.element{WaterfallCard(drama:d,rank:rk,colW:colW,coverH:coverH,playerDrama:$playerDrama)}
            }}
            VStack(spacing:vGap){ForEach(Array(ri.enumerated()),id:\.offset){s in
                if case .cat(let ti,let sd)=s.element{CategoryCard(theme:categoryThemes[ti%categoryThemes.count],dramas:sd,colW:colW,playerDrama:$playerDrama)}
                else if case .drama(let d,let rk)=s.element{WaterfallCard(drama:d,rank:rk,colW:colW,coverH:coverH,playerDrama:$playerDrama)}
            }}
        }.padding(.horizontal,margin)
    }
}

// MARK: - Category Card
struct CategoryCard: View {
    let theme:CategoryTheme;let dramas:[DramaItem];let colW:CGFloat;@Binding var playerDrama:DramaItem?
    var body: some View {
        VStack(alignment:.leading,spacing:0){
            HStack(spacing:0){Text(theme.name).font(.system(size:16,weight:.bold)).foregroundColor(.white);Spacer();Image(systemName:"chevron.right").font(.system(size:14,weight:.bold)).foregroundColor(.white).padding(.trailing,8)}
                .padding(.bottom,10).padding(.top,2)
            ForEach(Array(dramas.prefix(4).enumerated()),id:\.element.id){idx,drama in
                Button{playerDrama=drama}label:{
                    HStack(spacing:0){
                        CoverImageView(url:drama.coverURL,cornerRadius:DB.posterRadius,width:44,height:56).padding(.trailing,8)
                        Text(drama.title).font(.system(size:13,weight:.medium)).foregroundColor(.white).lineLimit(2).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    }.padding(4).background(theme.subBg).cornerRadius(2)
                }.buttonStyle(.plain)
                if idx<3{Spacer().frame(height:4)}
            }
        }.padding(8).frame(width:colW).background(theme.bg).cornerRadius(2)
    }
}

// MARK: - Waterfall Card
struct WaterfallCard: View {
    let drama:DramaItem;var rank:Int=0;let colW:CGFloat;let coverH:CGFloat;@Binding var playerDrama:DramaItem?
    var body: some View {
        Button{playerDrama=drama}label:{
            VStack(alignment:.leading,spacing:0){
                ZStack(alignment: .topTrailing) {
                    CoverImageView(url: drama.coverURL, cornerRadius: DB.posterRadius, width: colW, height: coverH)
                    if let badge = drama.placementBadge {
                        HomeCardBadgeView(badge: badge)
                    }
                }
                Text(drama.title).font(.system(size:14,weight:.semibold)).foregroundColor(DT.Color.textPrimary).lineLimit(2).padding(.horizontal,6).padding(.top,10).padding(.bottom,6)
                footerRow.padding(.horizontal,6).padding(.bottom,8)
            }.frame(width:colW).background(DT.Color.bgCard).cornerRadius(2)
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var footerRow: some View {
        if let r=rankText(rank:rank){HStack(spacing:4){Text(r).font(.system(size:11)).foregroundColor(DT.brandGold);Image(systemName:"chevron.right").font(.system(size:9,weight:.bold)).foregroundColor(DT.brandGold)}}
        else{HStack(spacing:6){ForEach(drama.tags.prefix(2),id:\.self){tag in HStack(spacing:3){Text(tag.capitalized).font(.system(size:11));Image(systemName:"chevron.right").font(.system(size:8,weight:.bold))}.foregroundColor(DT.Color.textSecondary).padding(.horizontal,6).padding(.vertical,3).background(DT.Color.textPrimary.opacity(0.06)).cornerRadius(2)}}}
    }
}

// MARK: - Category Drama Card (Categories Tab 横滑卡片)
struct CategoryDramaCard: View {
    let drama: DramaItem
    @Binding var playerDrama: DramaItem?
    private let cardW: CGFloat = 100
    private var coverH: CGFloat { cardW * 4 / 3 }

    var body: some View {
        Button { playerDrama = drama } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CoverImageView(url: drama.coverURL, cornerRadius: DB.posterRadius, width: cardW, height: coverH)
                    if let badge = drama.placementBadge {
                        HomeCardBadgeView(badge: badge)
                    }
                }
                Text(drama.title)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textPrimary)
                    .lineLimit(2)
                    .frame(width: cardW, alignment: .leading)
                    .padding(.top, DT.Space.xs)
                Text(drama.formattedViewCount)
                    .font(DT.Font.small)
                    .foregroundColor(DT.Color.textTertiary)
                    .padding(.top, 2)
            }
            .frame(width: cardW)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Masonry Waterfall (with Ad Cards)
struct MasonryWaterfall: View {
    let dramas:[DramaItem];@Binding var playerDrama:DramaItem?;let containerW:CGFloat
    private var colW:CGFloat{(containerW-margin*2-hGap)/2};private var coverH:CGFloat{colW*4/3}
    private let adsPerInterval: Int = 8

    /// 用于跟踪广告展示
    @State private var showAdDetail: Bool = false
    @State private var tappedAdIndex: Int = 0

    var body: some View {
        let all = Array(dramas.enumerated())
        let left = all.filter { ($0.offset % 2) == 0 }
        let right = all.filter { ($0.offset % 2) != 0 }
        // 广告位总数
        let adCount = all.count / adsPerInterval

        ZStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: hGap) {
                    leftColumn(leftDramas: left)
                    rightColumn(rightDramas: right)
                }
                .padding(.horizontal, margin)

                // 底部剩余广告（如果总行数不够）
                if adCount > 0 {
                    ForEach(0..<adCount, id: \.self) { adIdx in
                        AdCardView(adIndex: adIdx) {
                            tappedAdIndex = adIdx
                            showAdDetail = true
                        }
                        .padding(.horizontal, margin)
                        .padding(.top, vGap)
                    }
                }
            }

            // 原生广告详情全屏覆盖
            if showAdDetail {
                NativeAdDetailView(adIndex: tappedAdIndex)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Left Column

    private func leftColumn(leftDramas: [(offset: Int, element: DramaItem)]) -> some View {
        VStack(spacing: vGap) {
            ForEach(Array(leftDramas.enumerated()), id: \.offset) { idx, entry in
                // 每 4 对（8个卡片）插入一个广告（在左列的第4、8、12...项之前）
                if idx > 0 && idx % 4 == 0 {
                    let adIdx = idx / 4 - 1
                    AdCardView(adIndex: adIdx) {
                        tappedAdIndex = adIdx
                        showAdDetail = true
                    }
                }
                WaterfallCard(drama: entry.element, rank: entry.offset + 1, colW: colW, coverH: coverH, playerDrama: $playerDrama)
            }
        }
    }

    // MARK: - Right Column

    private func rightColumn(rightDramas: [(offset: Int, element: DramaItem)]) -> some View {
        VStack(spacing: vGap) {
            ForEach(Array(rightDramas.enumerated()), id: \.offset) { idx, entry in
                WaterfallCard(drama: entry.element, rank: entry.offset + 1, colW: colW, coverH: coverH, playerDrama: $playerDrama)
            }
        }
    }
}
