package com.paolosantucci.foglietto.shared.recovery

import okio.FileSystem
import platform.Foundation.NSCalendar
import platform.Foundation.NSCalendarIdentifierGregorian
import platform.Foundation.NSCalendarUnitDay
import platform.Foundation.NSCalendarUnitHour
import platform.Foundation.NSCalendarUnitMinute
import platform.Foundation.NSCalendarUnitMonth
import platform.Foundation.NSCalendarUnitNanosecond
import platform.Foundation.NSCalendarUnitSecond
import platform.Foundation.NSCalendarUnitYear
import platform.Foundation.NSDate
import platform.Foundation.NSTimeZone

/**
 * iOS production factory for the recovery repository.
 *
 * Keeps okio an internal `implementation` dependency — Swift sees only the exported
 * [RecoveryRepository] interface via `IosRecoveryFactoryKt.createIosRecoveryRepository()`
 * (mirrors `IosSettingsFactoryKt.createIosSettingsRepository()`).
 *
 * ## `now` lambda — UTC NSCalendar decomposition (NFR-06)
 *
 * The injected clock decomposes [NSDate] via a UTC Gregorian [NSCalendar] into the 7 Int
 * fields of [RecoveryInstant]. No epoch arithmetic — no `timeIntervalSince1970`, no
 * `* 1000`, no `epochSeconds`/`epochMilliseconds`. Milliseconds are derived from the
 * `NSCalendarUnitNanosecond` component divided by 1 000 000 (nanosecond-field arithmetic,
 * not epoch math). The UTC timezone (`NSTimeZone.timeZoneWithName("UTC")`) ensures
 * filenames are timezone-independent and lexicographically chronological (FR-11, NFR-06).
 *
 * ## okio boundary (CM-4)
 *
 * `FileSystem` and `Path` are construction-time implementation details hidden behind the
 * factory. Swift never sees an okio type; no `export(...)` is needed or added to
 * `shared/build.gradle.kts`. The existing single `shared` source set + `isStatic = true`
 * framework already exposes [RecoveryRepository]/[RecoveryNote]/[RecoveryInstant] to Swift.
 *
 * Spec refs: §5.1.b, FR-05, FR-24, NFR-06; closes CM-3, records CM-4.
 *
 * Runtime: Kotlin/Native `platform.Foundation` interop — available only in `iosMain` /
 * Apple targets. Host-guarded in `shared/build.gradle.kts` via `HostManager.hostIsMac`;
 * never compiled on the Linux CI host.
 */
fun createIosRecoveryRepository(): RecoveryRepository =
    FileRecoveryRepository(
        fileSystem = FileSystem.SYSTEM,
        recoveryDir = recoveryBaseDir(),
        now = {
            val calendar = NSCalendar(calendarIdentifier = NSCalendarIdentifierGregorian)
            // UTC so filenames are timezone-independent and lexicographically chronological.
            // `timeZoneWithName("UTC")` is the reliably-bound Kotlin/Native companion factory
            // (NSTimeZone.timeZoneForSecondsFromGMT is not generated in the Foundation interop).
            calendar.timeZone = NSTimeZone.timeZoneWithName("UTC") ?: NSTimeZone.localTimeZone
            val units = NSCalendarUnitYear or
                NSCalendarUnitMonth or
                NSCalendarUnitDay or
                NSCalendarUnitHour or
                NSCalendarUnitMinute or
                NSCalendarUnitSecond or
                NSCalendarUnitNanosecond
            val c = calendar.components(units, fromDate = NSDate())
            RecoveryInstant(
                year = c.year.toInt(),
                month = c.month.toInt(),
                day = c.day.toInt(),
                hour = c.hour.toInt(),
                minute = c.minute.toInt(),
                second = c.second.toInt(),
                millis = (c.nanosecond / 1_000_000L).toInt(),
            )
        },
    )
