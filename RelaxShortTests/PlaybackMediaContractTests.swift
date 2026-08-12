import XCTest
@testable import RelaxShort

/// 播放/字幕合同定向测试：锁定后端 snake_case 响应 → PlayerMediaSource / 外挂字幕映射。
/// 数据形状与 app-server/v2 全局 SNAKE_CASE + EpisodePlayResponse 实际输出一致。
final class PlaybackMediaContractTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String,
                                      file: StaticString = #filePath, line: UInt = #line) -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = json.data(using: .utf8),
              let value = try? decoder.decode(T.self, from: data) else {
            XCTFail("JSON 解码失败: \(json)", file: file, line: line)
            preconditionFailure()
        }
        return value
    }

    // MARK: - MP4 无字幕

    func testMP4WithoutSubtitlesMapsToPlayableMP4AndEmptyTracks() {
        let dto = decode(EpisodePlayResponseDTO.self, """
        {
          "episode_id": 102,
          "content_language": "en",
          "source_type": "mp4",
          "master_url": null,
          "fallback_mp4_url": "https://media.example.com/e/102/video.mp4",
          "qualities": [
            {"quality": "1080p", "url": "https://media.example.com/e/102/1080.mp4",
             "width": 1920, "height": 1080, "bitrate_kbps": 5000,
             "codec": "h264", "file_size": 104857600, "vip_required": false}
          ],
          "subtitle_tracks": [],
          "default_subtitle_language": null,
          "thumbnail_track": null,
          "resume_time": 0,
          "cdn_ready_status": 2,
          "asset_version": 3
        }
        """)

        let source = PlaybackMediaSourceDTO(from: dto)
        XCTAssertEqual(source.toPlayerMediaSource(),
                       .mp4(URL(string: "https://media.example.com/e/102/video.mp4")!))
        XCTAssertTrue(source.toPlayerSubtitleTracks().isEmpty)
    }

    // MARK: - MP4 + VTT 外挂字幕

    func testMP4WithVTTSubtitleMapsExternalTrackAndDefaultLanguage() {
        let dto = decode(EpisodePlayResponseDTO.self, """
        {
          "episode_id": 103,
          "content_language": "en",
          "source_type": "mp4",
          "fallback_mp4_url": "https://media.example.com/e/103/video.mp4",
          "qualities": [],
          "subtitle_tracks": [
            {"lang": "en", "url": "https://media.example.com/e/103/en.vtt",
             "type": "vtt", "is_default": false, "is_auto_generated": false}
          ],
          "default_subtitle_language": "en",
          "cdn_ready_status": 2
        }
        """)

        let source = PlaybackMediaSourceDTO(from: dto)
        XCTAssertEqual(source.toPlayerMediaSource(),
                       .mp4(URL(string: "https://media.example.com/e/103/video.mp4")!))

        let tracks = source.toPlayerSubtitleTracks()
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].languageCode, "en")
        XCTAssertEqual(tracks[0].url, URL(string: "https://media.example.com/e/103/en.vtt"))
        XCTAssertEqual(tracks[0].format, .vtt)
        // is_default=false，但 default_subtitle_language=en，应仍标记为默认轨
        XCTAssertTrue(tracks[0].isDefault)
    }

    // MARK: - HLS + MP4 fallback + VTT

    func testHLSWithFallbackAndVTTKeepsBothPlaybackSourceAndExternalSubtitles() {
        let dto = decode(EpisodePlayResponseDTO.self, """
        {
          "episode_id": 101,
          "content_language": "en",
          "source_type": "hls_with_fallback",
          "master_url": "https://media.example.com/e/101/master.m3u8",
          "fallback_mp4_url": "https://media.example.com/e/101/fallback.mp4",
          "qualities": [
            {"quality": "720p", "url": "https://media.example.com/e/101/720p.m3u8",
             "width": 1280, "height": 720, "bitrate_kbps": 2400,
             "codec": "h264", "file_size": 12345678, "vip_required": false}
          ],
          "subtitle_tracks": [
            {"lang": "en", "url": "https://media.example.com/e/101/en.vtt",
             "type": "vtt", "is_default": true, "is_auto_generated": false},
            {"lang": "zh", "url": "https://media.example.com/e/101/zh.vtt",
             "type": "vtt", "is_default": false, "is_auto_generated": true}
          ],
          "default_subtitle_language": "en",
          "thumbnail_track": {"sprite_url": "https://media.example.com/e/101/sprite.jpg",
                              "width": 160, "height": 90, "columns": 5, "rows": 5,
                              "interval_seconds": 5},
          "resume_time": 12,
          "cdn_ready_status": 1,
          "asset_version": 7
        }
        """)

        let source = PlaybackMediaSourceDTO(from: dto)
        XCTAssertEqual(
            source.toPlayerMediaSource(),
            .hlsWithFallback(
                masterURL: URL(string: "https://media.example.com/e/101/master.m3u8")!,
                fallbackMP4URL: URL(string: "https://media.example.com/e/101/fallback.mp4")!
            )
        )

        let tracks = source.toPlayerSubtitleTracks()
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].languageCode, "en")
        XCTAssertTrue(tracks[0].isDefault)
        XCTAssertEqual(tracks[0].format, .vtt)
        XCTAssertEqual(tracks[1].languageCode, "zh")
        XCTAssertFalse(tracks[1].isDefault)
    }

    // MARK: - 完整 snake_case 合同解码（字段名与后端全局 SNAKE_CASE 一致）

    func testSnakeCaseEpisodePlayJSONDecodesFullContract() {
        let dto = decode(EpisodePlayResponseDTO.self, """
        {
          "episode_id": 101,
          "content_language": "en",
          "source_type": "hls_with_fallback",
          "master_url": "https://media.example.com/e/101/master.m3u8",
          "fallback_mp4_url": "https://media.example.com/e/101/fallback.mp4",
          "auto_max_height": 720,
          "has_1080_entitlement": false,
          "qualities": [
            {"quality": "1080p", "url": null,
             "width": 1920, "height": 1080, "bitrate_kbps": 5000,
             "codec": "h264", "file_size": 204800000, "vip_required": true,
             "selectable": false}
          ],
          "subtitle_tracks": [
            {"lang": "en", "url": "https://media.example.com/e/101/en.vtt",
             "type": "vtt", "is_default": true, "is_auto_generated": false}
          ],
          "default_subtitle_language": "en",
          "thumbnail_track": {"sprite_url": "https://media.example.com/e/101/sprite.jpg",
                              "width": 160, "height": 90, "columns": 5, "rows": 5,
                              "interval_seconds": 5},
          "signed_expire_at": null,
          "resume_time": 12,
          "cdn_ready_status": 1,
          "asset_version": 7
        }
        """)

        XCTAssertEqual(dto.episodeId, 101)
        XCTAssertEqual(dto.sourceType, "hls_with_fallback")
        XCTAssertEqual(dto.masterUrl, "https://media.example.com/e/101/master.m3u8")
        XCTAssertEqual(dto.fallbackMp4Url, "https://media.example.com/e/101/fallback.mp4")
        XCTAssertEqual(dto.defaultSubtitleLanguage, "en")
        XCTAssertEqual(dto.qualities?.count, 1)
        XCTAssertEqual(dto.qualities?.first?.quality, "1080p")
        XCTAssertEqual(dto.qualities?.first?.vipRequired, true)
        XCTAssertEqual(dto.qualities?.first?.selectable, false)
        XCTAssertEqual(dto.autoMaxHeight, 720)
        XCTAssertEqual(dto.has1080Entitlement, false)
        XCTAssertEqual(dto.subtitleTracks?.count, 1)
        XCTAssertEqual(dto.subtitleTracks?.first?.isDefault, true)
        XCTAssertEqual(dto.subtitleTracks?.first?.isAutoGenerated, false)
        XCTAssertEqual(dto.thumbnailTrack?.spriteUrl, "https://media.example.com/e/101/sprite.jpg")
        XCTAssertEqual(dto.thumbnailTrack?.intervalSeconds, 5)
        XCTAssertEqual(dto.resumeTime, 12)
        XCTAssertEqual(dto.cdnReadyStatus, 1)
        XCTAssertEqual(dto.assetVersion, 7)
    }

    // MARK: - Feed 卡片 preview_episode_id → DramaItem → Series 播放合同

    func testFeedCardPreviewEpisodeIDMapsToDramaItemAndSeriesNav() throws {
        let feed = decode(ForYouFeedResponseDTO.self, """
        {
          "items": [
            {
              "series_id": 888,
              "preview_episode_id": 101,
              "localized_title": "Test Drama",
              "localized_synopsis": "Synopsis",
              "cover_url": "https://cdn.example.com/covers/888.jpg",
              "horizontal_cover_url": "https://cdn.example.com/covers/888-wide.jpg",
              "display_flags": ["NEW"],
              "tags": ["drama"],
              "play_asset": {
                "hls": "https://media.example.com/e/101/master-720p.m3u8",
                "standard_hls": "https://media.example.com/e/101/master-720p.m3u8",
                "mp4_fallback": "https://media.example.com/e/101/fallback.mp4",
                "subtitles": [
                  {"lang": "en", "url": "https://media.example.com/e/101/en.vtt",
                   "type": "vtt", "is_default": true, "is_auto_generated": false}
                ]
              },
              "monetization": {"is_free": true, "vip_required": false, "unlock_coin_cost": 0},
              "content_language": "en",
              "view_count": 1234,
              "category": "Drama",
              "episode_count": 20,
              "free_episode_range": {"start": 1, "end": 3}
            }
          ],
          "next_cursor": "0:5",
          "has_more": true,
          "matched_language": "en"
        }
        """)

        let card = try XCTUnwrap(feed.items?.first)
        XCTAssertEqual(card.seriesId, 888)
        XCTAssertEqual(card.previewEpisodeId, 101)
        XCTAssertEqual(card.playAsset?.subtitles?.count, 1)
        XCTAssertEqual(card.playAsset?.subtitles?.first?.lang, "en")

        let drama = FeedCardDTOMapper.toDramaItem(from: card)
        XCTAssertEqual(drama.id, "888")
        XCTAssertEqual(drama.previewEpisodeID, "101")
        XCTAssertEqual(card.playAsset?.standardHlsMasterUrl,
                       "https://media.example.com/e/101/master-720p.m3u8")
        XCTAssertEqual(drama.videoURL, "https://media.example.com/e/101/master-720p.m3u8")
        XCTAssertEqual(
            drama.toPlayerMediaItem()?.source,
            .hls(masterURL: URL(string: "https://media.example.com/e/101/master-720p.m3u8")!)
        )
        XCTAssertEqual(drama.isPublicPreview, true)

        // 普通卡片导航默认以 preview_episode_id 为目标，进入 Series 后单独请求 /play 合同
        let nav = SeriesPlayerNav(drama: drama, startEpisode: 1, sourceScene: "feed")
        XCTAssertEqual(nav.episodeID, "101")
        XCTAssertEqual(
            PlayerMediaItem.stableID(dramaID: drama.id, episodeNumber: nav.startEpisode),
            "888-1"
        )
    }
}
