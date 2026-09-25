# Status Trio memory footprint baseline (2026-09-24)

## Scope and environment

This is a read-only observation of the already-running process. No signal was sent and the app was not relaunched. It is **not a cold-start baseline** and cannot satisfy the plan's controlled scenario or three-run acceptance gate.

| Field | Observed value |
|---|---|
| Executable | `/Users/lingsmbp/Documents/aiwork/status-trio/dist/StatusTrio.app/Contents/MacOS/StatusTrio` |
| App version/build | 1.3.2 (15), from `dist/StatusTrio.app/Contents/Info.plist` |
| Executable SHA-256 | `8d19d62938fc67f6848a378c6b0fdbed437341be720bff29f95ff7aea80c5cbe` |
| Repository HEAD | `6505cd8be09d58ec85347f2265e50b835203d830` |
| Code signing | Ad-hoc; `TeamIdentifier=not set` |
| OS / architecture | macOS 27.0 (26A428), arm64 |
| Local toolchain | Xcode 27.0 (27A266a), Swift 6.4; this is not the plan's CI toolchain |
| Minimum OS | 15.0 |
| Power | AC attached, battery 80%, **not charging** |
| Display | 4096×2304 physical, UI Looks like 2048×1152 @ 100 Hz (2× backing scale) |
| App placement | `appIconPlacement=menuBar` |
| Process at first observation | PID 33850; elapsed 53:50–54:18 |
| UI history | Whether popover, Settings, or Dock UI had been opened is unknown. No controlled interaction state was established. |
| Build SDK | Not recorded in the app's Info.plist (`DTSDKName` absent); cannot certify this artifact's SDK from this run. |

## Samples captured

Commands used for the initial observations:

```sh
ps -p 33850 -o pid,etime,rss,command
footprint -p 33850
vmmap -summary 33850
```

| Local time (CST) | Process state / elapsed | RSS | `footprint` current / peak | `vmmap -summary` physical total | Notes |
|---|---:|---:|---:|---:|---|
| 19:27:52 | Running / 53:56 | 226,672 KB | 129 MB / 535 MB | 129.1 MB dirty; 77.3 MB malloc-zone resident | First complete read. |
| 19:28:20 | Running / 54:18 | 226,496 KB | 129 MB / 535 MB | 129.0 MB dirty; 77.1 MB malloc-zone resident | Second complete read, 28 seconds later. |
| 19:28:51 | PID absent | unavailable | unavailable | unavailable | `ps` had no row; `footprint` and `vmmap` reported PID no longer running. |
| 19:29:21 | PID absent | unavailable | unavailable | unavailable | Confirmed absent; no relaunch attempted. |

The two complete observations are nearly unchanged over 28 seconds: RSS differs by 176 KB and reported footprint stays 129 MB. This says nothing about a cold idle trajectory or a long-run slope. The recorded peak is lifetime high water and its cause/time are unknown.

### Major regions in the complete samples

`footprint` category values (dirty unless noted):

| Category | 19:27:52 | 19:28:20 |
|---|---:|---:|
| Malloc Small | 73 MB | 73 MB |
| CoreAnimation | 13 MB | 13 MB |
| CG Raster Data | 14 MB | 12 MB |
| CG Image | 4.5 MB | 4.5 MB |
| IOSurface | 3.2 MB | 3.2 MB |
| Stack | ~0.4 MB | ~0.4 MB |

The vmmap malloc-zone summary at 19:27:52 reported 39.7 MB allocated and 32.0 MB fragmentation in the default malloc zone. Across malloc zones it reported 41.9 MB allocated and 34.2 MB fragmentation. These are allocator accounting figures, not proof of a leak. No allocation backtraces or Instruments Allocations trace were collected.

## Limits and next measurement protocol

- The process was already approximately 54 minutes old when observed; prior activity and UI state are unknown. The observed 129 MB must not be labeled a cold-start value or regression.
- The process vanished during sampling, apparently independently of this read-only measurement. The cause is unknown; no crash or user action is inferred.
- The original long-running process has only two complete samples, 28 seconds apart. One fresh menu-bar-only run was sampled at 2:23; the exact nominal 2:00 point, 10/60-minute points, and additional launches for a three-run median are missing. There is no v1.2.1 comparator, no controlled popover/Settings/Dock state, and no charging A/B result.
- macOS 27.0 and local Xcode/Swift are outside the plan's macOS 26 / Xcode 26.6 / Swift 6.3.3 CI environment. The app artifact's SDK was not verified.

For a valid baseline, on a later authorized session when a fresh app launch is safe, record the exact binary and environment, explicitly confirm a fresh process and menu-bar-only placement, then save timestamped `ps`, `footprint`, and full `vmmap -summary` output at 2, 10, and 60 minutes. Repeat that cold-idle run three times. Capture popover and Settings open/closed states as separate controlled runs, and Dock placement separately. Use the same OS, artifact style, and metric for any v1.2.1 comparison. If heap attribution is needed, use a debuggable build with Instruments Allocations and Malloc Stack Logging. Do not use this partial observation to select a production optimization task.

## Fresh menu-bar-only idle sample

Following confirmation that `pgrep -x StatusTrio` returned no process and that the persisted placement was `menuBar`, the existing `dist/StatusTrio.app` was launched once. No popover or Settings window was opened during this run; no settings were changed. The app was left running after measurement.

| Field | Observation |
|---|---|
| Launch time | 2026-09-24 19:31:10 CST |
| Sample time | 2026-09-24 19:33:33 CST |
| Elapsed | 2:23 (sample taken 23 seconds after the nominal 2-minute point) |
| Process | PID 48824; still running at sample time |
| Scenario | Fresh launch, menu-bar placement, popover and Settings unopened |
| RSS | 58,672 KB |
| `footprint` | 17 MB current; 18 MB peak |
| `vmmap -summary` | 17.4 MB dirty total; 10.5 MB malloc-zone resident |
| Major `footprint` regions | Malloc Small 9,840 KB; CoreAnimation 32 KB; CG Raster Data not listed; CG Image 80 KB; Stack 224 KB; IOSurface not listed |

The fresh menu-bar-only sample is substantially below the earlier long-running process sample (17 MB versus 129 MB physical footprint; 58,672 KB versus 226,496 KB RSS). Because the earlier process had unknown UI history and this is one run on macOS 27.0, this difference does not isolate an interaction cost or establish a build regression. It is a single observation, not a median.

The 10-minute and 60-minute points, additional two-minute launches for a three-run median, and controlled popover/Settings/Dock scenarios remain outstanding. Keep PID 48824 running; capture later idle points against this same process only if it remains the same process and no UI is opened.

### Follow-up observation with Settings visible

| Local time (CST) | Process state / elapsed | RSS | `footprint` current / peak | `vmmap -summary` physical total | Notes |
|---|---:|---:|---:|---:|---|
| 19:35:01 | Running / 3:51 | 162,080 KB | 71 MB / 339 MB | 70.7 MB physical | Settings' App Icon pane was visible when inspected. The time at which the window became visible is unknown, so this is not a controlled before/after delta. |

At this observation, `vmmap` attributed about 33.7 MB dirty/resident to Malloc Small, 5.36 MB to CoreAnimation, 5.2 MB to CG Raster Data, 3.3 MB to CG Image, 0.27 MB to IOSurface, and 0.34 MB to stack. Compared with the earlier 17 MB sample, both elapsed time and UI state changed; the increase cannot be assigned to opening Settings. The 339 MB peak is lifetime high water and likewise has no known trigger. A controlled preview open/close sample is still required.

At elapsed 6:55, the same PID reported RSS 174,960 KB and current footprint 83 MB (peak still 339 MB). `Malloc Small` was 43 MB, `CoreAnimation` 9.2 MB, `CG Raster Data` 8.2 MB, and `CG Image` 4.3 MB. This short follow-up is another observation with Settings visible, not evidence of a steady growth slope; the view state and allocations during the interval were not controlled.

The Settings window was then closed through its normal close shortcut. At 19:39 (elapsed about 8:02), the process reported RSS 188,960 KB and footprint 90 MB (peak 362 MB). At 19:40:38 (elapsed 9:28), with no app window open for roughly one minute, it remained at RSS 188,880 KB and footprint 90 MB. Categories at the settled sample were Malloc Small 51 MB, CoreAnimation 9.5 MB, CG Raster Data 8.2 MB, and CG Image 2.3 MB. This suggests the window interaction left allocations resident for at least one minute, but the window-open time and exact initiating action are unknown, so it still does not isolate a specific preview render or prove an object leak. It does support prioritizing an instrumented preview open/close A/B.

At elapsed 11:28 (19:42 CST), about 3:26 after closing the Settings window, the same process remained at 90 MB footprint and 188,192 KB RSS. This is a settled post-interaction retention sample, **not** the plan's cold 10-minute point.

### Matched cold-idle repeat (2026-09-24)

To compare the base and preview-optimized code on the same machine with the same bundle ID and saved `menuBar` preference, I relaunched each release app and left its UI unopened. Both were built with the same macOS 26 SDK; base is the v1.3.2 (15) app already in `dist`, and the candidate is built from the optimized worktree as v1.3.3 (16). These are one-run samples, not three-run medians.

| Build | Local sample time (CST) | Elapsed | RSS | `footprint` current / peak | `vmmap` physical | Malloc Small | CG Image | CG Raster Data | CoreAnimation |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Base v1.3.2 (15) | 20:05:39 | 2:19 | 61,888 KB | 17 / 17 MB | 17 MB | 9.5 MB | 80 KB | not listed | 32 KB |
| Candidate v1.3.3 (16) | 20:08:21 | 2:19 | 58,304 KB | 17 / 17 MB | 17 MB | 9.4 MB | 80 KB | not listed | 32 KB |

The cold-idle physical footprint is unchanged at the tool's 1 MB display precision, with no new graphics footprint visible. This is consistent with the preview cache being lazy and having no idle Dock allocation when Settings and the guide are unopened. An earlier 44 MB reading used a fresh, different bundle ID and occurred while the Mac was locked, so the UI state and preferences were not controlled; it is excluded from this comparison. The original 17 MB sample and this repeat also remain below 100 MB physical footprint, while RSS is about 58–62 MB. The later one-hour base soak is recorded below.

### Candidate Settings App Icon interaction sample (single run, user-confirmed)

The optimized v1.3.3 (16) worktree app was launched with the existing `menuBar` preference, then the user opened Settings → App Icon and later closed the window normally. No setting values were changed. The process remained PID 68125 throughout. These readings use `footprint` for physical footprint and `ps` RSS; the Activity Monitor process row independently showed 53.0 MB at the first idle observation. The app was built locally from the candidate worktree with macOS 26 SDK (`LC_BUILD_VERSION`: `minos 15.0`, `sdk 26.0`).

| Local time (CST) | User-confirmed state | Process elapsed | RSS | `footprint` current / peak | Notes |
|---|---|---:|---:|---:|---|
| 20:37:02–20:40:40 | Menu-bar app, before the Settings interaction | 4:11–8:39 | 142,032–142,528 KB | 53 / 314 MB at initial sample | Repeated idle reads stayed near 53 MB / 142 MB. The user's UI state was not independently visible to the automation. |
| 21:29:57–21:30:53 | Settings → App Icon open, confirmed by user | 57:06–58:02 | 160,432–160,944 KB | 71 / 357 MB | Six readings over about one minute stayed near 71 MB / 160 MB. |
| 21:34:08–21:35:04 | Settings window closed normally, confirmed by user | 1:01:17–1:02:13 | 158,208–158,288 KB | 66 / 357 MB | Six readings over about one minute stayed near 66 MB / 158 MB. |

The open-page sample was about 18 MB above the earlier idle observation in both physical footprint and RSS. Within roughly a minute of closing, physical footprint fell by about 5 MB and RSS by about 2 MB, but neither returned to the earlier idle values. The first idle sample and Settings sample are from the same PID and binary, but they are separated by about 49 minutes with no measurements in between; this is not a tightly paired before/after run and does not establish that opening Settings caused the entire difference. The candidate's 71 MB open / 66 MB post-close physical footprint is below 100 MB, while its RSS remains above 100 MB. The earlier base-app Settings observations (71–90 MB physical) had unknown window-open timing, so neither comparison proves a memory reduction from the preview change.

The desktop controller could not attach to this menu-bar-only app, so the user confirmed the App Icon page and close state manually; process metrics were collected directly from the same PID. For causal before/after evidence, repeat the same interaction with the base v1.3.2 binary under the same preference and OS, and use identical open duration and post-close sampling windows. Current evidence supports the expected lazy preview allocation in cold idle and a modest observed drop after close, but does not establish the optimized build's Settings memory savings against base.

### Clean menu-bar-only idle recheck (candidate, no UI opened)

Because the preceding candidate process had gone through a Settings interaction, it was terminated normally and a new process was launched from the same optimized worktree app. `appIconPlacement` was verified as `menuBar`. During this run, no Settings, popover, or Dock UI interaction was issued. The app remained PID 74858 for the full sample.

| Local time (CST) | Process elapsed | RSS | `footprint` current / peak | `vmmap -summary` physical / malloc-zone resident | Notes |
|---|---:|---:|---:|---:|---|
| 21:40:56 | 0:15 | 62,160 KB | 17 / 17 MB | not captured | First sample after launch. |
| 21:43:24 | 2:43 | 62,528 KB | 18 / 18 MB | 18 / 10.9 MB | Malloc Small 10 MB; CG Image 80 KB; CoreAnimation 32 KB; CG Raster Data not listed. |
| 21:51:41 | 11:00 | 62,608 KB | 18 / 18 MB | 18 / 10.9 MB | Malloc Small 10.1 MB; CG Image 80 KB; CoreAnimation 32 KB; CG Raster Data not listed. |

Repeated reads between the table rows stayed at 17–18 MB physical footprint and 62.0–62.7 MB RSS. No upward trend appeared over 11 minutes. On the same machine, the base v1.3.2 cold-idle sample was 17 MB footprint / 61,888 KB RSS at 2:19, while the first v1.3.3 candidate sample was 17 MB / 58,304 KB at 2:19. This supports that the preview work does not add meaningful memory while Settings and Dock previews are never opened. The later one-hour base soak below checks the earlier high reading at the same process age.

### Clean base menu-bar-only idle soak (60 minutes)

To check whether the earlier 129 MB sample at process age 53:56–54:18 could be reproduced by long idle time alone, the base v1.3.2 (15) app was relaunched from the same `dist/StatusTrio.app`, with `appIconPlacement=menuBar`. No popover, Settings window, or Dock UI was opened. PID 75578 remained alive throughout the run, launched at 21:53:40 CST. The Activity Monitor process row was also refreshed during the run and showed about 17.9 MB of Actual Memory.

| Local sample time (CST) | Elapsed | RSS | `footprint` current / peak | `vmmap` physical / peak | Malloc Small resident | Total malloc-zone resident |
|---|---:|---:|---:|---:|---:|---:|
| 22:03:55 | 10:15 | 62,784 KB | 18 / 18 MB | 18 MB / 18 MB | 10.2 MB | 11.0 MB |
| 22:47:41 | 53:58 | 62,816 KB | 18 / 18 MB | 18.0 MB / 18.2 MB | 9,824 KB | 11.1 MB |
| 22:48:13 | 54:33 | 62,832 KB | 18 / 18 MB | — | — | — |
| 22:56:03 | 1:02:23 | 62,816 KB | 18 / 18 MB | 18.0 MB / 18.2 MB | 9,824 KB | 11.1 MB |

Repeated five-minute reads through the run stayed at 18 MB physical footprint and roughly 62.4–62.9 MB RSS. The 54-minute comparison point remained at 18 MB, so elapsed idle time alone did not reproduce the earlier 129 MB physical footprint / 226 MB RSS. At one hour, `vmmap` still showed only about 11.1 MB resident across malloc zones, 80 KB of CG Image, and 32 KB of CoreAnimation. This rules out a simple monotonic idle-time growth in this controlled run; it does not explain the old process, whose UI history and exact executable were not established. A production change should wait for the 100+ MB report to be matched to a specific metric, process/version, and menu-bar-only interaction history.

### Post-popover and permission interaction sample

After the one-hour clean-idle soak, the user opened and closed the status popover and handled Wi-Fi and Bluetooth permissions, then ran the same process checks. The process remained PID 75578 (base v1.3.2 build 15 from `dist/StatusTrio.app`):

| Sample | Process elapsed | RSS | `footprint` current / peak | Key details |
|---|---:|---:|---:|---|
| Before interaction, clean idle | 1:02:23 | 62,816 KB | 18 / 18.2 MB | No Settings, popover, or Dock UI had been opened in this soak. |
| User command after popover/permission interaction | 1:19:02 | 178,528 KB | 81 / 383 MB | Malloc Small 56 MB; IOSurface 3.5 MB; owned graphics 2.2 MB. |
| Follow-up samples, 23:15–23:17 | 1:21–1:23 | 178,432–178,464 KB | 81 / 383 MB | Closed UI; footprint stayed at 81 MB for about two minutes. |

`vmmap -summary` at elapsed 1:20:16 reported 80.7 MB physical footprint. The default malloc zone had 54.0 MB resident, including 28.2 MB allocated and 25.9 MB fragmentation (48%). `Malloc Small` resident was 47.0 MB; additional allocations were in `Malloc Small (empty)`, graphics, IOSurface, and image regions. The interaction sequence therefore correlates with a persistent same-process increase from 18 MB to 81 MB, but it combines popover use with permission handling and cannot assign the growth to one trigger.

The Activity Monitor screenshot shows 111.9 MB and four threads, but its PID and capture time are not visible. In a later live read, Activity Monitor showed PID 75578 at 95.5 MB while `top` and `footprint` reported about 81 MB. The 111.9 MB screenshot should therefore be treated as a user-observed Activity Monitor value, not as a directly paired footprint sample. An Allocations trace attempt against PID 75578 failed to attach, so no allocation call stacks are available yet.

The measured v1.3.2 process kept a popover-only Bluetooth monitor active after close. The v1.3.3 candidate in PR #71 changes that lifecycle: popover-only activation stops on close, while an explicit Settings toggle still keeps the monitor active. Its cold-idle samples remain low, but they do not measure the post-popover delta; the next controlled run should isolate popover-only activation from permission handling and compare the same `footprint` categories before and after close.

### Fresh candidate menu-bar-only recheck (2026-09-25)

A new v1.3.3 (16) process from Actions run 36021302008 was launched through Computer Use from the verified candidate DMG, with the saved `appIconPlacement=menuBar` preference. No Settings, status popover, or Dock UI was opened during this run. PID 91335 remained alive through the samples below.

| Local sample time (CST) | Elapsed | RSS | `footprint` current / peak | `vmmap` physical | Malloc-zone resident / allocated |
|---|---:|---:|---:|---:|---:|
| 2026-09-25 00:33:02 | 3:30 | 61,728 KB | 18 / 18 MB | 17.6 MB | 10.7 / 12.0 MB |
| 2026-09-25 00:36:06 | 6:34 | 62,000 KB | 18 / 18 MB | — | — |
| 2026-09-25 00:37:06 | 7:34 | 62,000 KB | 18 / 18 MB | — | — |
| 2026-09-25 00:38:06 | 8:34 | 62,144 KB | 18 / 18 MB | — | — |
| 2026-09-25 00:39:06 | 9:34 | 62,080 KB | 18 / 18 MB | — | — |
| 2026-09-25 00:40:06 | 10:34 | 62,128 KB | 18 / 18 MB | — | — |
| 2026-09-25 00:40:45 | 11:13 | 62,080 KB | 18 / 18 MB | 17.9 MB | 11.0 / 12.2 MB |

The fresh candidate stayed at 18 MB physical footprint for the entire 11-minute sample, with RSS varying by less than 0.5 MB. The 11:13 `vmmap -summary` showed 11.0 MB resident across malloc zones and no default-zone fragmentation. This is another clean-idle run, not a post-popover test. It supports keeping production changes focused on the interaction-triggered 18→81 MB growth already recorded above; it does not attribute that growth to Bluetooth, Wi-Fi permission handling, or SwiftUI individually.

At elapsed 15:01, `heap -s -H` reported 12.2 MB allocated across 36,806 malloc nodes, with 17.9 MB physical footprint and an 18.1 MB peak. About 9.4 MB was categorized as non-object allocations; the largest named object category was 292 KB of `NSMutableDictionary` storage. The heap sample confirms that this fresh idle process does not have a large reachable object graph. It still cannot explain the earlier post-interaction allocation without a matched post-popover heap/Allocations sample.

### Candidate menu-only state after closing a visible Settings window (single run)

When Computer Use reconnected on 2026-09-25, the candidate process's Settings → App Icon window was already visible. Its open time and the actions before reconnection are unknown. I closed that window normally with `Command-W`; the Status Trio process stayed at PID 91335 and the menu-bar icon remained. This is a post-interaction observation, not a clean cold-idle run or a controlled before/after test.

| Local sample time (CST) | State / elapsed | RSS | Activity Monitor Memory column | `footprint` current / peak | `vmmap` physical / malloc zone | Heap allocated / nodes |
|---|---|---:|---:|---:|---:|---:|
| 2026-09-25 10:22:24 | Settings closed / 9:52:52 | 168,672 KB | 69.0 MB | 69 / 326 MB | 69.1 / 48.8 MB resident | — |
| 2026-09-25 10:22:54–10:24:25 | Settings closed / 9:53–9:55 | 174,208–174,256 KB | 69.0 MB | 69 / 326 MB | — | — |
| 2026-09-25 10:25:06 | Settings closed / 9:55:34 | 174,208 KB | 69.0 MB | 69 / 326 MB | 69.4 / 48.8 MB resident | 45.2 MB / 287,393 |

The Activity Monitor inspector for the same PID showed 164.7 MB Actual Memory, 56.2 MB private, and 174.2 MB shared; its process-list Memory column showed 69.0 MB, matching `footprint` at that time. RSS therefore must not be substituted for the Memory column or physical footprint. `vmmap` attributed 44 MB to Malloc Small, 2.6 MB to CG Image, 1.8 MB to CoreAnimation, and 1.5 MB to owned graphics. The heap sample was 45.2 MB across 287,393 nodes, versus 12.2 MB across 36,806 nodes in the earlier fresh idle sample. Thus the process had a persistent post-interaction physical footprint of 69 MB while only the menu-bar icon was visible; the Settings window's earlier visibility is correlated context, not a proven cause. It stayed flat across the roughly two-minute follow-up.

One interim shell sample printed 20 MB because its `pgrep -f` expression matched the sampling shell rather than PID 91335; that reading is invalid and excluded. All values above use the confirmed PID directly. The next useful step is a controlled debug/Allocations trace around opening and closing Settings or the popover, with exact state timestamps. Do not change production code based on this single non-isolated trace; the live heap delta is real, but its retaining owners are not identified.

An Allocations trace attach was attempted against PID 91335 with a five-second time limit. `xctrace` announced the attach but remained unresponsive for more than one minute, leaving only a 96-byte incomplete `.trace` directory; the agent's xctrace process was then terminated. No allocation data was produced. Retry with a debuggable app launched under Instruments rather than attaching to this release process, and capture the UI interaction while the trace is active.

### Allocations launch-path validation (debug-only; excluded from footprint comparisons)

The worktree's Debug bundle initially had no `com.apple.security.get-task-allow` entitlement. Re-signing that local-only bundle with the entitlement let `xctrace record --template Allocations --launch` produce a 111.96-second trace. This validates a way to collect allocation events for a debug launch; it does not validate attaching to or tracing the release process. The test preference was temporarily `appIconPlacement=both`, so this run was not menu-bar-only. Instruments reported 28.3 MiB current heap allocations and 110.2 MiB anonymous VM; 84.05 MiB was `VM: Performance Tool Data`, so the instrumented process totals are not comparable to release `footprint` samples. The trace contained no Settings or popover interaction. The test preference was reset to the app's default afterward, and the debug process was stopped. The remaining gap is a visible UI trigger during a trace; CUA cannot bind to the app after its last window closes or activate its menu-bar item.

### Full-permission popover run (popover closed; Settings-window state unconfirmed)

The user confirmed Wi-Fi, Bluetooth, VPN, and audio-input permissions were ready and that the status popover was open. The tested process was the development bundle `com.lingsmbp.StatusTrio.dev.memory-footprint-opt`, version 1.3.2 (15), PID 45918. The user was asked to close the popover and leave Settings closed while a five-minute sample ran, then confirmed the popover was closed during that sample. Whether a Settings window was also closed throughout that sample has not been separately confirmed. Computer Use could not inspect the menu-bar-only popover directly.

| Local sample time (CST) | Reported state | `footprint` current / peak | `vmmap` physical / Malloc Small | Heap allocated / nodes |
|---|---|---:|---:|---:|
| 2026-09-25 11:35:12 | All permissions ready; popover open | 82 / 503 MB | 81.8 MB / 52 MB | 35.9 MB / 201,270 |
| 2026-09-25 11:35:47–11:40:55 | Popover closed (user confirmed); Settings window state unconfirmed | 80 MB throughout | 80.2 MB / 52 MB at 11:37:59 | 33,259,787 bytes / 162,002 at 11:39:51 |

The heap retained about 2.6 MB fewer allocated bytes and 39,268 fewer nodes than the open-panel sample, while physical footprint stayed near 80 MB and Malloc Small stayed at 52 MB. This is consistent with freed heap blocks remaining resident in malloc pages, but it does not prove that interpretation: heap summaries do not identify allocation owners, and the Settings-window state was not confirmed. Repeat with both the popover and Settings window confirmed closed, then compare heap bytes, malloc-zone resident pages, and footprint after the 60-second content-release delay before changing code.

The user subsequently clarified that the popover was closed during this run. At 11:54:44, with PID 45918 still running and the popover closed, `footprint` remained 81 MB (peak 503.4 MB), `vmmap` reported 81.3 MB physical and 52 MB in Malloc Small, and `heap -s -H` reported 32.3 MB across 168,104 malloc nodes. The Settings-window state remains unconfirmed. This confirms the post-close footprint is persistent well beyond the controller's 60-second popover-content release delay.

### Attached Allocations trace (same development process)

An Allocations instrument was attached to PID 45918 for 3:01 while the popover was opened and closed; the user confirmed it was closed for the follow-up samples. In `Created & Destroyed`, Instruments attributed 634.4 MB of cumulative allocation to `BluetoothHIDUsageReader.read()` through `IORegistryEntryCreateCFProperties` / `IOCFUnserializeBinary`, within 667.2 MB attributed to a Dispatch workloop thread. These bytes were created and destroyed during the trace. Switching the same trace to `Created & Persistent` showed only about 1.5 MB total allocated during the recording still live at its end, including 65.97 KB under worker threads; it did not show the pre-existing 80 MB footprint because recording began after that memory had already accumulated. The Bluetooth HID walk is therefore a measured high-allocation-churn path, but this trace does not establish that it owns the post-close resident heap. The current sample also contains about 608 KB of Instruments' `Performance Tool Data`, excluded from comparisons to an uninstrumented run.

The HID reader previously asked IOKit to materialize every property dictionary for every `IOHIDDevice`, then filtered for Bluetooth and read four properties. It now requests only `Transport` first, then `DeviceAddress`, `PrimaryUsagePage`, and `PrimaryUsage` for Bluetooth services. Tests pin both the lookup order and the early exit for non-Bluetooth devices. A fresh runtime trace is still needed to quantify the allocation reduction and compare post-close `Malloc Small` resident pages; this code change does not establish that the retained 80 MB was caused by the HID walk.

Verification on this Mac: `swift test` passed (351 tests / 60 suites), `swift build -c release` passed, and `git diff --check` passed. The local environment is Xcode 27.0 / Swift 6.4 / macOS 27 SDK, while CI uses Xcode 26.6 / Swift 6.3.3; the local build is therefore not proof of CI-toolchain compatibility. PID 45918 was gracefully stopped, and the rebuilt, ad-hoc-signed development bundle was launched as PID 59584 with the same bundle identifier, version 1.3.2 (15), and `Memory Footprint Opt` codename. Its saved placement remained `menuBar`.

### Fresh optimized-build menu-bar-only idle sample

After launching PID 59584, no Settings window, popover, or Dock UI was opened. Repeated samples through elapsed 6:59 stayed at 17–18 MB `footprint`, with RSS around 58–59 MB. `system_profiler.*SPBluetoothDataType` was absent when checked. At elapsed 4:49, `vmmap -summary` reported 17.8 MB physical footprint and 9.9 MB in `Malloc Small`; `heap -s -H` reported 12.2 MB across 37,184 nodes. At 6:59, footprint remained 18 MB and RSS was 59,408 KB. This fresh-run sample does not reproduce the 80–111 MB post-interaction observation and confirms the menu-bar-only cold-idle path remains small. Since no popover was opened, it does not measure the changed HID property lookup or explain memory retained after an interaction.

### Popover use on the rebuilt development bundle (Bluetooth authorization not verified)

The user opened and then closed the popover on PID 59584. At 13:18:23 CST (process elapsed 11:02), `footprint` was 51 MB, `vmmap -summary` physical was 50.6 MB, Malloc Small resident/allocated was 26.5 MB, and the heap had 23.7 MB across 87,290 nodes. No `system_profiler.*SPBluetoothDataType` process was present at the sample instant. The current build is ad-hoc signed and was rebuilt after the prior permission setup; this sample does not establish whether Bluetooth authorization was granted, denied, or not determined, nor whether a profiler read had already completed. Do not use it as the full-permission comparison. Repeat after confirming Bluetooth is allowed for this exact development build, then close the Settings window and popover before sampling the same PID.

### Bluetooth authorization restored on the optimized build

The user confirmed Bluetooth permission was granted for the rebuilt development app. PID 59584 remained running. At 13:23:18, the process had 73 MB `footprint`; at 13:24:07, it had settled to 70 MB `footprint` and 70.5 MB physical footprint. RSS was 158,432 KB at 13:24:07. No `system_profiler.*SPBluetoothDataType` process was present at the sample instant. At the time of these idle samples, opening the popover after restoring permission had not yet been confirmed; the controlled open/read/close follow-up is recorded below.

### Full-permission popover open/close after restoring Bluetooth authorization

The user confirmed Bluetooth permission was granted, then opened the status popover and closed both it and the Settings window. PID 59584 was unchanged. No `system_profiler.*SPBluetoothDataType` process was present at either sample instant (the optimized HID reader uses direct IOKit property reads, so this check is not proof that its Bluetooth scan did or did not run).

| Local sample time (CST) | State / elapsed | RSS | `footprint` current / peak | `vmmap` physical | Malloc Small resident | Heap nodes / allocated |
|---|---|---:|---:|---:|---:|---:|
| 2026-09-25 13:26:30 | Popover and Settings closed; immediate / 19:09 | 163,280 KB | 76 / 414.6 MB | 75.6 MB | 41.0 MB | 173,704 / — |
| 2026-09-25 13:27:51 | Closed / 20:30; 81 sec later | 162,608 KB | 73 / 414.6 MB | 73.5 MB | 40.7 MB | 134,356 / 29.7 MB |

The measured footprint fell 3 MB during the follow-up minute, then remained about 3 MB above the 70.5 MB authorized-idle sample taken before this interaction. This suggests a small persistent post-interaction delta in the current run, not the earlier 10+ MB delta, but the before sample was already after an earlier popover use and therefore is not a clean cold-idle baseline. The malloc node count fell by about 39,000 while resident Malloc Small pages changed only 0.3 MB, consistent with freed heap objects leaving allocator pages resident; the sample does not identify their retaining owners. The earlier full-permission run on PID 45918 remained near 80 MB after close, but its Settings-window state was unconfirmed, so the 73.5 MB result is directionally lower rather than a controlled causal comparison. Do not infer that Bluetooth authorization itself adds 3 MB or that the targeted IOKit change alone accounts for the difference.

### Stable post-close heap inspection

At 13:31:22, PID 59584 remained at 73.5 MB physical footprint and 29.6 MB across 134,311 malloc nodes, about four minutes after the 13:27:51 sample. `heap -s -H` categorized 17.4 MB as non-object allocations; its largest named categories were Swift metadata (2.9 MB), Objective-C method-cache buckets (1.3 MB), and several MB spread across CoreSVG/CGPath objects. `leaks -q --noContent` found 417 candidate blocks totaling about 20 KB, mostly system XPC reference cycles, far too little to explain the live heap. A `leaks --trace` inspection of one 278,528-byte non-object block found roots through the app's long-lived monitor task storage and SwiftUI AttributeGraph/Metal-owned structures, but this restricted process has no allocation backtraces and those pointer paths do not prove which subsystem allocated the block. The remaining post-interaction memory therefore has no confirmed app-level retaining owner. A controlled Allocations or malloc-stack-logging trace around the next panel interaction is still needed before changing the SwiftUI/cache lifetime further.

At process age 3:26:58, a filtered `leaks --referenceTree` follow-up found only a 208 KB AttributeGraph malloc-zone metadata region, a 48 KB SwiftUI localization mapping with 0 KB dirty, and two 16-byte IOSurface references under the shared RenderBox surface pool. It did not expose a retaining tree for the 278,528-byte blocks or identify an app-owned allocation source. The process footprint was 75 MB at this sample, within 1.5 MB of the earlier 73.5 MB post-close reading; this small change during additional inspection is not evidence of a growth trend. These filtered system-framework references do not justify another UI-cache or monitor-lifetime code change without allocation stacks.

### VPN monitoring is limited to popover visibility

`VPNStatus` is a popover-only value and `MenuBarStatus` does not include VPN. `SystemStatusStore` now starts its VPN observer and update consumer when the popover opens, reads immediately for the row, and stops the observer and consumer when it closes. Hidden fallback ticks, Settings refreshes, and wake recovery while the popover is closed no longer run VPN reads. Each temporary stop finishes that consumer's stream generation and prepares a fresh stream for the next opening; deinitialization cancels the observer and finishes the current stream.

This removes background VPN monitoring work while the popover is hidden. It has not been measured in a rebuilt app and is not expected to reclaim the existing interaction high-water: PID 59584 still showed about 73.5 MB physical footprint and 29.6 MB heap after the popover closed; `leaks` reported about 20 KB. The VPN change addresses idle observer/read work and provides no evidence about which UI or framework allocation retains that footprint.

Local verification after the VPN lifecycle change: focused VPN/store lifecycle tests passed (7 tests); the full `swift test` run passed (351 tests / 60 suites), `swift build -c release` passed, and `git diff --check` passed. This does not verify the CI toolchain (Xcode 26.6 / Swift 6.3.3); because the change touches deinit cleanup, run the repository's non-publishing release workflow before merging or publishing.
