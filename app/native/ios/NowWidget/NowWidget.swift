// DaySet '지금' 위젯 (iOS 17 이상, 인터랙티브 위젯)
//
// 버튼을 누르면 앱을 열지 않고 App Intent가 실행되어 공유 저장소(App Group)에
// 탭 기록을 쌓는다. 앱은 켜지거나 앞으로 올 때 그 기록을 가져가 반영한다.
// 저장 키와 형식은 lib/platform/widget_bridge.dart 와 같아야 한다.

import AppIntents
import SwiftUI
import WidgetKit

private let appGroupId = "group.com.dayset.dayset"
private let keyPending = "pending_events"
private let keyCurrent = "current_activity"
private let keySince = "current_since"

// MARK: - 상태

enum NowActivity: String, CaseIterable, AppEnum {
    case sleep, meal, work, exercise, rest

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "상태"
    static let caseDisplayRepresentations: [NowActivity: DisplayRepresentation] = [
        .sleep: "수면", .meal: "식사", .work: "업무", .exercise: "운동", .rest: "휴식",
    ]

    var label: String {
        switch self {
        case .sleep: return "수면"
        case .meal: return "식사"
        case .work: return "업무"
        case .exercise: return "운동"
        case .rest: return "휴식"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz"
        case .meal: return "fork.knife"
        case .work: return "briefcase"
        case .exercise: return "figure.run"
        case .rest: return "cup.and.saucer"
        }
    }
}

// MARK: - 공유 저장소

enum SharedStore {
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupId) }

    static func append(_ activity: NowActivity, at date: Date) {
        guard let d = defaults else { return }
        let stamp = ISO8601DateFormatter().string(from: date)  // 예: 2026-10-14T00:40:00Z

        let raw = d.string(forKey: keyPending) ?? "[]"
        var list = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[String: String]] ?? []
        list.append(["activity": activity.rawValue, "at": stamp])
        if list.count > 50 { list.removeFirst(list.count - 50) }

        if let data = try? JSONSerialization.data(withJSONObject: list),
           let json = String(data: data, encoding: .utf8)
        {
            d.set(json, forKey: keyPending)
        }
        d.set(activity.rawValue, forKey: keyCurrent)
        d.set(stamp, forKey: keySince)
    }

    static var current: NowActivity? {
        guard let raw = defaults?.string(forKey: keyCurrent), !raw.isEmpty else { return nil }
        return NowActivity(rawValue: raw)
    }
}

// MARK: - App Intent (버튼 동작)

struct StartActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "지금 상태 바꾸기"
    static let openAppWhenRun = false

    @Parameter(title: "상태")
    var activity: NowActivity

    init() {}

    init(activity: NowActivity) {
        self.activity = activity
    }

    func perform() async throws -> some IntentResult {
        // 같은 상태를 다시 누르면 아무것도 하지 않는다(앱 규칙과 같음).
        if SharedStore.current != activity {
            SharedStore.append(activity, at: Date())
        }
        return .result()
    }
}

// MARK: - 타임라인

struct NowEntry: TimelineEntry {
    let date: Date
    let current: NowActivity?
}

struct NowProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowEntry {
        NowEntry(date: .now, current: .work)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        completion(NowEntry(date: .now, current: SharedStore.current))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        // 버튼을 누르거나 앱이 updateWidget을 부르면 다시 그린다.
        completion(Timeline(entries: [NowEntry(date: .now, current: SharedStore.current)], policy: .never))
    }
}

// MARK: - 화면

private let accent = Color(red: 14 / 255, green: 107 / 255, blue: 90 / 255)

struct NowWidgetView: View {
    let entry: NowEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.current.map { "\($0.label) 중" } ?? "지금 무엇을 하나요?")
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(NowActivity.allCases, id: \.self) { a in
                    let on = a == entry.current
                    Button(intent: StartActivityIntent(activity: a)) {
                        VStack(spacing: 3) {
                            Image(systemName: a.symbol)
                            Text(a.label).font(.caption2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? accent : Color.gray.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(a.label) 시작")
                }
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

@main
struct NowWidget: Widget {
    let kind = "NowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowProvider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName("지금 상태")
        .description("누르면 앱을 열지 않고 바로 기록해요.")
        .supportedFamilies([.systemMedium])
    }
}
