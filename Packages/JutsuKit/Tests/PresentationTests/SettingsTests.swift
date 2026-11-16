import Foundation
import JutsuCore
import Testing

@testable import Presentation

extension UserDefaultsBackedTests {
    @Suite struct AppSettingsTests {
        func defaults() throws -> UserDefaults {
            let name = "SettingsTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.removePersistentDomain(forName: name)
            return defaults
        }

        @Test func disabledCapIsNil() throws {
            let defaults = try defaults()
            defaults.set(false, forKey: AppSettings.spendCapEnabledKey)
            #expect(AppSettings.spendCap(in: defaults, for: .apiKey) == nil)
            defaults.set(true, forKey: AppSettings.spendCapEnabledKey)
            defaults.set(-3.0, forKey: AppSettings.spendCapUSDKey)
            #expect(AppSettings.spendCap(in: defaults, for: .apiKey) == .usd(75))
        }

        @Test func accountCapIsInCredits() throws {
            let defaults = try defaults()
            defaults.set(true, forKey: AppSettings.spendCapCreditsEnabledKey)
            #expect(AppSettings.spendCap(in: defaults, for: .account) == .credits(1_000))
            defaults.set(250, forKey: AppSettings.spendCapCreditsKey)
            #expect(AppSettings.spendCap(in: defaults, for: .account) == .credits(250))
            defaults.set(0, forKey: AppSettings.spendCapCreditsKey)
            #expect(AppSettings.spendCap(in: defaults, for: .account) == .credits(1_000))
            defaults.set(false, forKey: AppSettings.spendCapEnabledKey)
            #expect(AppSettings.spendCap(in: defaults, for: .account) == .credits(1_000))
        }

        @Test func emptyOrUnknownValuesReadAsDefaults() throws {
            let defaults = try defaults()
            #expect(AppSettings.defaultModel(in: defaults) == nil)
            #expect(AppSettings.cacheMaxAge(in: defaults) == nil)
            #expect(AppSettings.cellularDownloads(in: defaults))
            defaults.set("generated", forKey: AppSettings.defaultAudioKey)
            defaults.set("7:5", forKey: AppSettings.defaultAspectRatioKey)
            defaults.set(7, forKey: AppSettings.cacheMaxAgeDaysKey)
            let form = CreateForm(settings: defaults)
            #expect(form.audio == AppSettings.defaultAudio && form.aspectRatio == AppSettings.defaultAspectRatio)
            #expect(form.model == .genjutsu && form.mode == AppSettings.defaultMode)
            #expect(AppSettings.cacheMaxAge(in: defaults) == TimeInterval(7 * 86_400))
        }

        @Test func migrationMovesNotifySwitchAndDropsRetiredKeys() throws {
            let defaults = try defaults()
            defaults.set(false, forKey: AppSettings.notifyOnDoneKey)
            defaults.set(true, forKey: "settings.showInMenuBar")
            defaults.set(Data(), forKey: "images.models.account.someone")
            defaults.set("mute", forKey: AppSettings.defaultAudioKey)
            AppSettings.migrate(defaults)
            let preferences = AppSettings.notificationPreferences(in: defaults)
            #expect(!preferences.onDone && !preferences.onProblems)
            #expect(defaults.object(forKey: "settings.showInMenuBar") == nil)
            #expect(defaults.object(forKey: "images.models.account.someone") == nil)
            #expect(AppSettings.defaultAudio(in: defaults) == .mute)
        }
    }
}

@Suite struct DailySpendTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let noon = Date(timeIntervalSince1970: 1_760_356_800)  // 2025-10-13 12:00 UTC

    func job(_ state: JobState, cost: Cost, finishedAt: Date? = nil) -> Job {
        let source = SourceClip(
            fileURL: URL(fileURLWithPath: "/tmp/source.mov"), duration: 10,
            pixelSize: PixelSize(width: 1280, height: 720), range: 0...10)
        let spec = JobSpec(mode: .motionTransfer, source: source, references: [], resolution: .p480)
        var job = Job(spec: spec, providerKind: .apiKey, cost: cost)
        job.state = state
        job.finishedAt = finishedAt
        return job
    }

    @Test func countsTodaysFinishedAndEveryActiveJob() {
        let jobs = [
            job(.done, cost: .usd(10, isEstimate: false), finishedAt: noon),
            job(.done, cost: .usd(100, isEstimate: false), finishedAt: noon - 86_400),
            job(.queued, cost: .usd(Decimal(string: "2.5")!, isEstimate: true)),
            job(.paused(.insufficientFunds), cost: .usd(1, isEstimate: true)),
            job(.failed(reason: .message("x")), cost: .usd(50, isEstimate: false), finishedAt: noon),
            job(.canceled, cost: .usd(50, isEstimate: false), finishedAt: noon),
            job(.processing, cost: .credits(500, isEstimate: true)),
        ]
        #expect(DailySpend.committed(jobs, on: noon, calendar: calendar) == Decimal(string: "13.5"))
    }

    /// A charged job whose download failed counts on the day it was charged, and only then.
    @Test func countsAChargedJobWhoseDownloadFailedOnItsDay() {
        var failed = job(.failed(reason: .message("download")), cost: .usd(3, isEstimate: false), finishedAt: noon)
        failed.chargedAt = noon
        let done = job(.done, cost: .usd(10, isEstimate: false), finishedAt: noon)
        #expect(DailySpend.committed([failed, done], on: noon, calendar: calendar) == 13)
        #expect(DailySpend.committed([failed], on: noon + 86_400, calendar: calendar) == 0)
    }

    @Test func eachUnitIsCountedApart() {
        let jobs = [
            job(.done, cost: .credits(120, isEstimate: true), finishedAt: noon),
            job(.queued, cost: .credits(30, isEstimate: true)),
            job(.done, cost: .usd(10, isEstimate: false), finishedAt: noon),
        ]
        #expect(DailySpend.committed(jobs, on: noon, in: .credits, calendar: calendar) == 150)
        #expect(DailySpend.committed(jobs, on: noon, in: .usd, calendar: calendar) == 10)
    }
}

@Suite struct NotificationPermissionTests {
    @Test func asksOnlyWhenTurningOnBeforeIOSAsked() {
        #expect(NotificationPermission.notAsked.asks(whenTurning: true))
        #expect(!NotificationPermission.notAsked.asks(whenTurning: false))
        #expect(!NotificationPermission.denied.asks(whenTurning: true))
        #expect(!NotificationPermission.allowed.asks(whenTurning: true))
    }
}
