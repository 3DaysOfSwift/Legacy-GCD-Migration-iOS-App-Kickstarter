# Kickstarter migration behaviour contract

## View-owned transient-message delays — 29 October 2026

Keep the existing banner (4/10 seconds), save-error toast (3 seconds) and copy-link
confirmation (2.5 seconds) timing, content and animation. SwiftUI owns these tasks;
removal cancels them. Banner replacement restarts its lifetime and stale identity
cannot clear a replacement binding. Toast dismissal remains change-triggered rather
than starting for an initially supplied error. Hosted runtime checks cover banner
replacement and removal; other gesture/accessibility/device behavior remains open.

## Project-page media and audio-session lifetime — 29 October 2026

- Preserve per-row AVPlayer instances, optional cached WebP thumbnails and the
  existing audio/video cells. Thumbnail availability must not delay player readiness.
- ProjectMediaFeature owns pending preparation per page/slot. Equivalent pending
  requests share; changed media replaces that slot. Page replacement/exit cancels
  preparation and rejects stale delivery. Separate pages and rows stay independent.
- Native asset loading is awaited. Readiness observation finishes on ready, failure
  or cancellation and is always invalidated. KVO notifications may omit their typed
  new value; capture the item's current status at the callback boundary instead.
- A late row result may not overwrite a different URL/thumbnail or a removed row.
- One production audio controller serves both the framework and tests. Retain the
  existing soloAmbient/playback policy, OS gating and hardware/unmute intentions.
  Rebinding removes prior observers; dismissal/release finishes event observation.
  Reset completion belongs to its current generation and cannot reopen a dismissed feed.
- Resource cleanup must work for synchronous Objective-C/UIKit-style release as well
  as async release. Finite MainActor cleanup captures resources by value, never the
  deinitializing owner. Cleanup does not initiate new service work.
- Local PCM media and controlled callbacks validate ownership, not visual parity,
  real remote decoding/network behavior or physical-device audio routing/silent switches.

## Saved projects, reporting and account fields — 28 October 2026

- SAVE-01: Keep login gating, the 500ms debounce, optimistic selection, notification
  payloads, counts, saved-project prompts, accessibility, haptics and analytics.
- SAVE-02: Ordinary buttons and video-feed saves share ProjectMediaFeature's native
  queue and transient cache. Equivalent pending writes share; changed desired states
  execute in order per session/project. No automatic mutation retry is introduced.
- SAVE-03: Reused cells discard unadmitted debounced requests and their optimistic
  cache entry. Disposed observers do not cancel admitted mutations. Latest-intent
  and session-generation checks reject obsolete rollback, cache and UI results.
- REPORT-01: Keep option hierarchy, labels, email display, details, banners and
  dismissal behavior. ProjectReportingFeature owns these requests; screen-owned read tasks cancel on disappearance.
- REPORT-02: Equivalent pending reports share; different reports execute in session
  order. Missing context fails gracefully rather than force-unwrapping. Send is
  disabled and its existing spinner is active while submission is pending; explicit
  retry is restored on failure. Cancellation never claims to undo an accepted report.
- ACCOUNT-01: Account fields use SettingsFeature's shared async read, which waits
  for admitted account edits. Retain refresh timing, currency/email/warning/password
  decisions and navigation. Delayed output and deferred admission retain session
  identity. Controllers construct destinations; the ViewModel receives only a Feature.
- ACTION-01: Public-demo reporting and save writes fail explicitly. Live mutations,
  visual parity and physical-device behavior remain separate unverified gates.

Baseline: 30 original logic tests passed (23 saving/reporting, 7 account fields).
Original behavior assertions are retained with explicit async waits; one unsave
fixture now supplies an unsave response instead of silently completing without data.
The report submit spinner activates an existing loading control during the request;
this small pending-state correction is explicit, not a screen redesign.

## Friends and following — 28 October 2026

- FRIEND-01: Preserve Facebook connection gating, source attribution, friend order,
  concatenated pagination, terminal empty pages, statistics, loading behavior,
  discovery navigation, names/counts/accessibility and all existing screen layout.
- FRIEND-02: Keep follow-all confirmation, immediate list clearing after success,
  and the existing two-second refresh delay. A previous session's delayed refresh
  cannot start a request under a replacement account.
- FRIEND-03: One FriendsFeature owns transient follow state shared by Find Friends
  and Activity. Follow/unfollow/follow-all writes execute in admission order;
  identical pending tails share. Failures do not mutate confirmed state or retry.
- FRIEND-04: Reads belong to screen routes. Equivalent pending reads share, refresh
  supersedes pagination, and released routes or replaced accounts reject old values
  and errors. Page and statistics failures remain independent. New reads wait for
  admitted writes; follow-all invalidates any older page before delayed refresh.
- FRIEND-05: Cell reuse suppresses another friend's completion. Observer disposal
  does not cancel an admitted remote write. Session changes reject late cache
  commits and delayed presentation, including logout/login to the same user ID.
- FRIEND-06: Native requests retain existing routes, methods, cursor and body fields.
  The fictional demo rejects follow mutations. No live service mutation is implied
  by mock success, and cancellation cannot undo a server-accepted write.

Baseline: 25 original logic tests passed. Their behavior assertions are retained
with explicit async waits. New controlled tests cover ownership and ordering.
Full checkpoint results and limits are recorded in the ledger and sibling
Migration Evidence/kickstarter-friends. Visual/device and live-service checks remain open.


## Pledged-project overview and payment plans — 28 October 2026

- PPO-01: Preserve card parsing, tier flags, order, page counts, empty/error/loading
  states, dashboard/card analytics, navigation, banners and existing screen layout.
- PPO-02: Share equivalent pending pages; refresh supersedes pagination. Screen
  release or account replacement prevents late results. Terminal load-more returns.
- PPO-03: Order address/receipt writes. A single receipt failure produces one error
  banner and refresh; success retains optimistic feedback. Preserve negative address
  acknowledgement/progress behavior. Never retry writes automatically.
- PPO-04: Public demo rejects mutations. Disposed screens stop observing but cannot
  undo admitted writes. Old-account outcomes cannot publish into a new session.
- PLAN-01: Preserve amount formatting, eligibility/context/default selection and
  payment errors. Bind each plan to its requesting project; replaced amounts,
  released routes and account changes reject old responses.

25 original baseline tests passed. Final integrated run: 1,378 passed, zero
failures/skips, app build succeeded. Eighteen new cases cover ownership and
presentation. Existing parent pledge assertions now await plan completion.
Live payments, visual/device validation and app-wide concurrency remain open.


## Payment methods and Stripe intents — 28 October 2026

- PAY-01: Preserve card ordering/availability, selection, optimistic deletion and
  rollback, edit/loading state, error/banner copy and payment-sheet configuration.
  Preserve the workaround filling a newly stored card's missing stripeCardId.
- PAY-02: Keep intent contexts, two-decimal amount formatting, encoded Checkout ID
  and existing nullable input mapping. Native stored-card reads fetch fresh data.
- PAY-03: Share equivalent pending intents and equivalent pending card-write tails.
  Distinct card writes run in order; failure does not retry or block later commands.
  Reads wait for writes and refetch when overtaken.
- PAY-04: Screen disposal cancels observation, not an admitted mutation. Native
  reads honor cancellation; obsolete session values/errors and delayed secrets
  cannot be delivered to a replacement session.
- PAY-05: Public demo rejects every payment entry point. Never infer a successful
  payment from an intent, or assume cancellation reverses a server-accepted write.

Baseline: 69 original tests passed. Final integrated run: 1,147 passed with zero
failures/skips and successful app build; includes ten new controlled Feature tests.
Original screen assertions retained with explicit async fixture lifetimes and one
completed card-list fixture. Compile failures and two test-fixture crashes are
recorded in the ledger/evidence. Real Stripe authorization/charges, live account
operations, visual/device parity, remaining checkout/pledge ownership and full
app-wide validation are still open.

## Messaging — 28 October 2026

- MSG-01: Preserve inbox/sent/project scope, refresh clearing, concatenation,
  empty-page stop, loading/footer behavior and current navigation.
- MSG-02: Search clears immediately and cancels obsolete work before debounce.
  Late success/error cannot restore a cleared query or change newer loading.
  Disappearing screens cannot admit a pending debounced request.
- MSG-03: Preserve sorted messages, backing lookup rules, role-based empty copy,
  recipient labels, untrimmed bodies and blocking/read-status effects.
- MSG-04: Share equivalent pending sends and read-status writes. Distinct sends
  remain ordered per destination; a failed send does not automatically retry.
  Screen disposal suppresses presentation without canceling an admitted write.
- MSG-05: Reject stale account generations, including same-user replacement,
  and suppress delayed presentation after session changes.
- MSG-06: Keep native endpoint/query/body encoding and reject account messaging
  in the fictional demo. Deep links use the same MessagingFeature.

Baseline 36 original tests passed. Final 1,063 integrated tests passed, zero
failures/skips, and app build succeeded. Includes 15 new Feature/lifetime cases,
one deep-link test and three native request/demo tests. All original messaging
assertions retained. See ledger/evidence for corrected fixtures and scheduler
synchronization failures. Live services, visual/device parity and app-wide
strict-concurrency validation remain open.

## Project-notification settings — 28 October 2026

- Preserve project names, list loading's silent failure, combined email/mobile
  switch, immediate optimistic feedback, existing error text and cache keys.
- Use the same GET/PUT routes and encoded channel fields. Never fabricate a
  successful account operation in the public fictional demo.
- Share equivalent pending tails; execute distinct edits in order per notification.
  Cell reuse/disposal stops presentation but cannot undo an admitted remote write.
- Commit only confirmed state for the current session. Suppress stale list results,
  old-session success/errors and delayed notifications after cell reuse.
- Intentional correction: rapid-edit failure returns to confirmed state rather than
  an earlier unconfirmed tap. Failure remains a failure; retry is explicit.

Baseline: all six original list/cell tests passed. Final: 1,008 integrated tests
passed, zero failures/skips; app build succeeded. Eight new ownership/lifetime cases
and two native route/decoder cases are included. The first runs omitted the new
test file from Xcode membership; that coverage gap was fixed and all eight named
results checked afterward. See the ledger and sibling Migration Evidence/
kickstarter-project-notifications. Live accounts, rendered/device parity,
full-suite and app-wide concurrency sign-off remain open.

## Shared activity badge — 28 October 2026

- Root tab and Activity callers share one pending badge-clear command and one
  session commit. Merge only its returned count into the latest current user.
- Preserve immediate tab-badge clearing, silent save failure, existing notification
  effects and tab layout. Retry is explicit; disposal cannot undo an admitted write.
- Suppress old-session results and delayed notifications. Completed badge changes
  invalidate older whole-user reads without cancelling unrelated setup metadata.
- Controllers notify after persistence; they must not replay returned User snapshots.

Baseline: 24 original Root tests. Final: 992 tests passed and app built, zero
failures/skips; six new scenarios. The Rewards fixture-cleanup crash, corrective
actor/lifetime changes and ten passing repeated runs are recorded in the ledger
and sibling Migration Evidence/kickstarter-root-badge. Exact runtime-abort cause
is not proven. No full-suite, live-service or visual/device sign-off is implied.

## Account writes and session refresh — 28 October 2026

- ACC-W01: Preserve account form validation, loading/errors, confirmation,
  navigation and notification effects; retain existing routes and encoded keys.
- ACC-W02: Account and preference writes execute in admitted order. Only an
  equivalent pending tail shares work. Failure does not strand the next edit.
- ACC-W03: Disposing presentation cannot cancel an admitted remote write.
  Old-session completions cannot persist into the replacement session.
- ACC-W04: Merge only the confirmed changed account fields into the latest
  session user. Facebook connection changes its connection/token flags, not a
  stale response's unrelated preferences. Live reconciliation remains unverified.
- ACC-R01: Refresh waits for queued settings writes; stale reads and stale errors
  are suppressed after account changes, including logout/login to the same ID.
- ACC-R02: Preserve cached-user-first Settings display. Only authenticated
  lifecycle refresh may restore a stored token's missing user; ordinary refresh
  never logs in. Setup email/PPO/features commit once through SessionFeature.
- ACC-V01: Verification links may execute while signed out, share equivalent
  pending tokens, order distinct tokens and never establish a session.
- ACC-D01: Public demo rejects account writes; no synthetic successful mutation.

Original assertions plus controlled SettingsFeature/SessionFeature tests protect
these requirements. Baselines: 37 account-form tests and 11 Settings tests;
Facebook original suite has post-change evidence only. Final: 962 tests passed,
zero failures/skips; app build succeeded. See MIGRATION_LEDGER.md and sibling
Migration Evidence/kickstarter-account-writes for commands, failures and limits.
UI source/layout is preserved; rendered/device and live account journeys have
NOT been signed off. This is an engineering checkpoint, not migration completion.

## Social/signup/OAuth and password reset — 28 October 2026

- Preserve existing Facebook errors and two-factor/confirmation routing, Apple
  SDK error handling, signup newsletter consent, reset validation/copy, navigation
  and session notifications. Layout and identifiers are unchanged.
- Treat Apple/OAuth token plus matching user as one operation. A partial failure,
  cancelled caller, superseding attempt or old session cannot persist credentials.
- Share equivalent pending signup/login requests; do not retry writes automatically.
  Preserve OAuth's pre-login analytics identity, once per committed shared attempt.
- Preserve existing REST routes, PKCE payload, both newsletter fields and Apple's
  mutation input. OAuth's temporary token overrides X-Auth only for its user request;
  it does not mutate the service or stored session before success.
- Reset is separate from login/resend and never establishes a session. Duplicate
  pending emails share; changed email replaces presentation. Disposal suppresses
  completion without claiming to reverse an already accepted remote write.
- OAuth browser/redirect work belongs to its screen adapter. Cancel/release and
  replaced browser/session generations cannot publish late authentication.
- Keep public demo account operations unavailable; no fictional successful login
  or password-reset send. No live account operation was performed in verification.

Intentional corrections: reset loading settles false after completion rather than
the old synchronous mock's reversed notification order; malformed Apple IDs show
failure rather than leaving loading active. Apple has one final artificial API
delay (default zero), not separate delays around both stages. Other existing
business assertions remain, with explicit async completion instead of timing guesses.

Baseline: 53 passed, two 10ms OAuth test timeouts. Final: 886 integrated tests passed,
zero failures/skips, app built with two existing warnings. Four nonvisual suites
retain per-suite snapshot-device opt-outs only. Thirteen new Feature/OAuth cases
and three native request tests are included. Results and limitations are recorded
in sibling Migration Evidence/kickstarter-auth-flows and MIGRATION_LEDGER.md.
No live-service, visual/device, full-suite or app-wide concurrency sign-off implied.

## Email login and two-factor authentication — 28 October 2026

- Preserve email/password and Facebook two-factor routes, request encoding,
  token/error decoding, validation, loading, resend messages and navigation.
- Commit successful login once through SessionFeature using the existing
  credential/current-user store before delivering presentation confirmation.
- Share equivalent pending attempts. Changed credentials/code replace the older
  attempt within that operation; verify request and session identity after await.
- Keep resend independent of submitted verification. Resend never creates a
  session, including an unexpected successful token response.
- Disposed/cancelled callers cannot commit. Disposing one shared caller does
  not cancel another. Same-user logout/login still invalidates prior attempts.
- Preserve failure delivery and explicit retry; public demo authentication fails
  rather than reporting synthetic success. No live authentication is performed.

Baseline: 21 unchanged Login/TwoFactor tests. Final: 815 integrated tests passed,
zero failures/skips, app build succeeded. Ten Feature and two decoder cases added.
Results: /private/tmp/kickstarter-authentication.juTwNe.
Evidence: sibling Migration Evidence/kickstarter-authentication, including the
reproduced Discovery lifecycle abort, test-lifetime cleanup and ten passing repeats.
Exact runtime-abort root cause remains unproven; failures are not erased by retry.

Initial Facebook/Apple/signup/OAuth/reset-password and other account flows remain
legacy. No whole-app, live-service, physical-device or visual sign-off is implied.

## Newsletter/deep-link preference entry points — 27 October 2026

- Preserve the post-pledge Games newsletter prompt, German opt-in text, silent
  save-failure behavior and user-updated notification after confirmed persistence.
- Preserve notification URL field names, enabled/disabled values, navigation and
  presentation delay. Unknown fields retain the legacy no-op save.
- Newsletter and notification links join the existing settings queue; a later
  edit must not overwrite an unrelated earlier edit from a stale User snapshot.
- Persist once in the Feature. Delayed UI callbacks may identify/notify the
  current user but must not re-save a completed command's old snapshot.

Baseline: 16 Thanks + 118 AppDelegate tests. After: 803 integrated tests passed,
zero failures/skips, app build succeeded. Six new cases cover all URL fields,
shared ordering, failure, signed-out/unknown input and delayed completion.
Evidence: /private/tmp/kickstarter-preference-entrypoints.ITOvsu and sibling
Migration Evidence/kickstarter-preference-entrypoints.
No live-service mutation or authenticated visual/device validation was run.
The older settings checkpoint below accurately describes its earlier boundary;
the two remaining updateUserSelf callers it lists are resolved by this checkpoint.

## Settings preferences and shared account persistence — 27 October 2026

- Preserve switch values, immediate visual feedback, rollback/error messages,
  German newsletter opt-in prompts, digest picker behavior and navigation.
- Preserve the user-self PUT route/encoding and existing account storage keys.
- Apply changed fields to the current session user when a queued write dispatches.
  Only equivalent pending tails share; distinct on/off/on intents remain ordered.
- Persist confirmed preferences before the next save. Screen disposal or caller
  cancellation does not abandon an admitted write; no automatic retry is added.
- Reject signed-out, mismatched-account and old-generation commands, including
  old failures after logout/login to the same ID. Invalid requests cannot reset
  another account's valid queue.
- Recommendations remain visually optimistic, but speculative values are no
  longer persisted as a full User. Failed writes leave authoritative state intact.
- Remove delayed controller persistence for migrated settings/Profile/Activity.
  Guard Profile responses through presentation delays and merge badge counts
  into the latest session user. Retain the existing UI notifications.
- The public fictional demo rejects preference writes; no synthetic success.

Baseline: 55 original settings tests passed. After: 642 integrated tests passed,
zero failures/skips, and the app built in
/private/tmp/kickstarter-settings-preferences.famRTj.
Thirteen SettingsFeature cases plus a delayed-Profile regression were added.
An earlier run had one test-process abort (605 passed); the identical full rerun
passed. Root cause of that intermittent XCTest/Swift runtime abort is unresolved.

Thanks newsletter signup and AppDelegate notification deep links remain legacy
writers of the same endpoint; app-wide write serialization is not complete.
Other account/authentication, messaging/project-notification and payment workflows
remain open. No live account mutation, authenticated visual/device sign-off,
full-suite pass or strict-concurrency completion is implied.

## Activity/Profile and shared account reads — 27 October 2026

- Preserve Activity's descending deduplicated history, refresh retention, empty
  first-page clearing, surveys, navigation, badge triggers and analytics.
- Preserve independent backed/saved pagination, cached header prefix, loading
  presentation, project-count refresh triggers and the one-second save debounce.
- Equivalent pending reads share. Refresh replaces pagination; completed saves
  invalidate older header reads. Late success/error cannot repopulate reset state.
- Validate account generation after suspension, including logout/login to the
  same ID. Login/logout resets both tab owners; signed-out private reads do not run.
- Combine successful header reads regardless of response order, explicitly fixing
  the old graph-first lost-update race. Independent display/error behavior remains.
- Admitted badge writes continue, but cannot update a newer account; no automatic
  retry after an uncertain remote mutation.
- AppEnvironment remains the sole credential/current-user persistence authority
  during this stage. No storage keys, branding, layout or login/logout effects changed.

573 tests passed with zero failures/skips and an app build succeeded:
/private/tmp/kickstarter-account-tabs.f1QiDO.
Existing expected values are retained. Sixteen controlled Feature tests cover
overlap, late replies, failure/retry, account change, reset and save invalidation.
No live badge/account mutation, populated authenticated UI, physical-device,
full-suite or strict-concurrency sign-off. Whole-app migration remains incomplete.

## Video-feed loading and save/watch — 27 October 2026

- Preserve the existing 30-item query, empty/error display and prior data on failed refresh.
- Publish initial-load completion before fetchedItems; optimistic saves update
  items only, without a collection reload. Preserve first-impression analytics.
- Preserve immediate saved state/count, login intent, cache reconciliation,
  mute preference, navigation and latest-intent failure toast/rollback.
- Share equivalent in-flight reads; reject released-route or old-account results.
- Order changed watch states per account/project; share equivalent pending
  commands and keep unrelated projects independent. No automatic remote-write retry.
- Navigation cancels feed reads, not admitted writes; queued old-account writes
  cannot dispatch and obsolete completions cannot alter visible state.

528 tests passed with zero failures/skips and the app built successfully in
/private/tmp/kickstarter-video-feed.gHPMre. Original 18 ViewModel assertions
remain; controlled tests cover completed success/failure and adverse ordering.
Live watch/unwatch, populated-feed visual parity, device and strict-concurrency
validation remain unexecuted. This is a bounded checkpoint, not app-wide sign-off.

## Discussion mutations — 27 October 2026

| ID | Preserved requirement | Protection |
| --- | --- | --- |
| DISC-W01 | Show a temporary comment immediately, replace by stable ID, retain failed text | Original Comments/Replies/Dialog assertions pass |
| DISC-W02 | Explicit retry shows retrying, retry-success for three seconds, then confirmed comment; failure returns original failed comment | Original timed tests pass; duplicate attempt sharing is Feature-tested |
| DISC-W03 | Distinct posts are not discarded; at most five execute concurrently | Controlled six-post admission/failure test |
| DISC-W04 | Block success posts the existing notification and analytics; failure remains visible | Original two-screen tests pass; Feature sharing/independence/failure tests |
| DISC-W05 | Screen disposal must not imply rollback of an admitted remote mutation | Disposed-subscriber/route-release test; existing Apollo adapter also did not cancel remote writes |
| DISC-W06 | Account changes cannot dispatch delayed old text or publish obsolete results | Controlled queued writes, retry/status delay and blocking tests |
| DISC-W07 | Cancelling one caller does not cancel shared mutation work; no automatic retry | Controlled waiter cancellation and failure/retry tests |

499 tests and app build passed in /private/tmp/kickstarter-discussion-writes.FuQBU3.
Existing optimistic dialog dismissal is preserved, not corrected as an incidental
redesign. Live-service/visual/device mutation checks remain unexecuted; no real
comment or block was submitted. This bounded checkpoint is not app-wide sign-off.

## Discussion reads and playback counters — 27 October 2026

- Preserve project-first configuration, update-only project context and current
  composer/keyboard/navigation behavior. Posting, retry and blocking stay legacy.
- Preserve returned page identity/cursors, backward replies and the empty-page
  stop condition. Missing envelopes complete silently; errors remain errors.
- Refresh clears as before. Reply retry after an initial failure must not emit
  an extra clear before the first successful reply count. Existing assertion passes.
- Separate route lifetimes, share equivalent in-flight reads, replace explicit
  refresh/changed navigation, and reject canceled/account-mismatched completions.
- Keep update WebKit policy, cached-project navigation, ref tags and silent lookup
  errors. No controller, layout or resource was redesigned.
- Video start/completion are independent events, not latest-wins reads. Preserve
  the playback threshold and once-per-screen triggers; never automatically retry
  a counter write with an unknown remote outcome. Playback UI remains unchanged.

454 integrated tests passed, zero failures/skips, and app build succeeded in
/private/tmp/kickstarter-discussion-media.ga9kgf. The 71-test baseline passed;
one post-change reply emission mismatch was corrected without weakening assertions.
Seven update-detail and 19 API tests also passed with zero failures/skips.
Agent smoke observed overview → Campaign → overview; the demo does not expose
populated discussion/video flows. Those are fixture-tested, not visually verified.
This is not live-service, visual parity, full-app or strict-concurrency sign-off.

## Shipping destinations and creator interactions — 27 October 2026

| ID | Preserved requirement | Protection and result |
| --- | --- | --- |
| SHIP-01 | Digital rewards make no shipping request and select nil; empty fetched destinations are a distinct successful result | Existing ViewModel and new Feature tests pass |
| SHIP-02 | Prefer valid backing location, then configured country, then US, then first destination | Existing nine shipping tests plus direct priority/fallback tests pass |
| SHIP-03 | Loading shows shimmer; error uses the existing localized message; picker select/cancel and 300 ms dismissal remain | Existing ViewModel assertions pass |
| SHIP-04 | Equivalent reads share; changed inputs supersede; independent selectors do not cross-cancel | Controlled suspension and adverse-completion tests pass |
| SHIP-05 | Cancellation/account change cannot deliver obsolete destinations; failure preserves previous data and retry recovers | Direct Feature tests pass |
| CREATOR-01 | Biography requests retain service preparation and message authorization reflects the current account | Feature and seven existing creator ViewModel tests pass |
| CREATOR-02 | Creator links preserve return-to-project, login, message and external-browser navigation | Existing creator assertions pass; updates/pledge-web adapters also regression-tested |

377 combined tests and app build passed:
/private/tmp/kickstarter-shipping-interactions.82bZbI.
Five location API tests also passed. Agent smoke observed overview/rewards/return
and creator-screen open/return. The demo is digital: no rendered shipping picker,
live creator content or transaction completion is claimed.
The nine shipping tests passed before migration. Creator baseline was blocked by
invalid synthetic WebKit object lifetime, not a navigation assertion failure.
The corrected fixtures preserve all navigation assertions and actual-event data.
New overlap tests strengthen obsolete-read protection without changing payment,
storage or visible design. No full-app, live-service or strict-concurrency claim.

## Rewards and related-project reads — 27 October 2026

- The shipping-sorted rewards API returns one complete list, not cursor pages.
  Preserve its query, server ordering, shipping metadata and synthetic No Reward
  placement experiment. Filter future rewards in the owning Feature.
- A changed shipping location supersedes that screen's read; equivalent in-flight
  requests share. Separate reward/project routes do not cancel each other.
  Cancellation and account changes suppress late results and errors.
- Keep cached reward cards bound to their last successful location after failure;
  retain the existing placeholder and retry-through-location-change behavior.
- Preserve secret/backed-reward scroll, selected reward, shipping rule, navigation,
  footer count, existing CTA decisions and analytics. No payment mutation changed.
- Recommendations load independently of required detail/backing/reward data.
  Preserve initial loading, loaded/empty/error presentation and card navigation.

Verification: 324 combined tests and app build passed in
/private/tmp/kickstarter-rewards-related.VmZxNu; two sorted-reward decoder tests
passed in /private/tmp/kickstarter-rewards-sorted-decoder.xcresult.
Agent smoke observed overview → Rewards → overview → Campaign. Public demo
does not supply recommendation cards; their rendering still needs visual/live
validation. No full-app or strict-concurrency completion claim.

## Project-detail loading checkpoint — 27 October 2026

Before: 75 existing page/tracking tests passed at bc6a50a01. After: all original
assertions retained, plus 12 Feature tests and one recommendations-rendering
regression; 293 combined tests and app build passed. Existing API fixture/decoder
contracts: 11 additional tests passed. No failures or skips in either final run.

| Requirement | Protection |
| --- | --- |
| Secret-reward enrollment precedes reads and failure prevents downstream work | Controlled enrollment gate and failure/retry tests |
| Standard project → optional backing → rewards ordering | Feature trace assertions, no partial-project publication |
| Backing merge retains project metadata; no-reward stays first | Direct Feature assertions plus existing API fixture contracts |
| Fast base/extras begin concurrently and either failure fails the page | Controlled parallel dependency tests; throwing task group cancels siblings |
| Repeated equivalent requests share; mutation refresh supersedes | Sharing and forced-refresh adverse completion tests |
| Independent project routes do not cross-cancel | Two-route cancellation/release test |
| Account changes and late responses cannot publish stale state | Controlled account/replacement tests |
| Existing preview, CTA, media, navigation and analytics outputs remain | 75 original assertions retained through async test adapters |
| Unrelated recommendations may still update a selected page | Explicit recommendations-error rendering regression; pending fixtures isolate other tests |

Agent smoke: Pocket Observatory overview → Campaign → FAQ → Rewards (demo
supporter edition) → same FAQ page. No payment, real account or enrollment used.
This does not verify the legacy rewards-screen executor, live APIs, snapshot
equivalence, full accessibility, device performance or app-wide completion.

## Explore async ownership checkpoint — 27 October 2026

Final continuation: 205 tests passed with zero failures/skips and the app built
in /private/tmp/kickstarter-discovery-async.RzwK5t. Selected filter state and
recommendation defaults now belong to DiscoveryFeature; all existing controller
output/analytics assertions still pass. Public filter selection does not eagerly
fetch hidden feeds. View models retain screen readiness/navigation timing.

Same filters under a different account no longer share in-flight work or reuse
an older account's cursor. A late project/activity response from the previous
account cannot publish. Direct regression tests cover both cases. Existing cached
card display behaviour is unchanged; this is not a full session/privacy audit.

Final Simulator smoke observed Games selection, Forest Trails and the selected
Games header, then All Projects restoring Pocket Observatory. No visual source
was changed. Other manual/strict-concurrency limitations below remain open.

Before: 55 existing Explore logic tests passed on commit
237d929d8c5c1e714935ccd959048e628e93ea07. After: those same assertions passed
through DiscoveryFeature's native async route; the combined run passed 202 tests,
zero failures/skips, and the app built. Results:
/private/tmp/kickstarter-discovery-async.vlaCu9.

| Requirement | Protection and result |
| --- | --- |
| Four retained sorts keep independent results and requests | New four-feed adverse-order test; existing sort/lifecycle tests passed |
| First-page loading, pull refresh, filter clearing and empty states keep existing presentation | All DiscoveryPageViewModelTests assertions retained; scheduler-only draining replaced with awaiting Feature task completion |
| Pagination appends in order without duplicates; empty page ends pagination | Existing testPaginating plus direct cursor/deduplication/termination test passed |
| Refresh retains cards until success and replaces pending pagination | Direct old-page-late regression passed; existing refresh/loading tests passed |
| Failures stop loading without inventing empty success; paging can retry | Feature retains errors separately; failed-page/same-cursor retry test passed; no new error UI |
| Equivalent in-flight callers share completion; superseded work cannot publish | Direct sharing, late-filter response and cancellation tests passed |
| Activity samples keep seen-ID storage and navigation behaviour | Existing activity/seen/clear/navigation assertions passed; new sample replacement/error/isolation tests passed |
| Session/filter/reachability/analytics presentation remains unchanged | Existing login, blocked-user, onboarding, banner and event assertions passed |
| Public demo remains usable without private API keys | Native MockService demo route test and running Simulator cards/detail observed |

The agent observed Magic, Popular, Newest and Ending Soon demo feeds, opened
Paper Cities from Ending Soon, then closed detail and observed the same selected
feed/cards. This is a bounded smoke check, not screenshot comparison, live-network
verification or authentication coverage. Manual pull-refresh was inconclusive
(the gesture opened a card), so only its automated coverage is claimed.

The final continuation above moved filter/recommendation policy into the Feature.
Screen readiness and navigation remain compatibility-view-model responsibilities. URLSession provides
native cancellation, but no live-server cancellation experiment was performed.
Swift 5 mode remains; full strict-concurrency and app-wide exit gates are open.

## Search checkpoint history

Latest confirmation (27 October): 189 tests passed, zero failures/skips, and app
build succeeded in /private/tmp/kickstarter-query-admission.7z1aJ3. This supersedes
the pending Search close-out and Explore logic-baseline notes below. The first
run exposed an actual sharing defect, now fixed: funding buckets and location
must participate in Search request identity even though legacy REST equality
omits them. All four now have cancellation/late-result regression coverage.
Manual/snapshot, strict-concurrency and app-wide completion remain outstanding.

Author: Matthew Thomas. Baseline captured 26 October 2026 at
`5ad48326904a4033e1b06ab21cb0942c51b077fe` (public-demo preparation).
Original upstream: `5f5463cfb830413d253efed45bfcec0322c9f152`.

This contract covers Search. Ownership, filters, async transport and native awaitable pagination have
incremental checkpoints recorded below. It is not a complete app contract, nor proof
that authentication, payments or live APIs work. UIKit presentation is retained.
Test names below refer to `LibraryTests/Library/ViewModels/SearchViewModelTests.swift`
unless another suite is named. The ledger records exact commands and results.

| ID | Plain-English requirement | Legacy evidence | Evidence status | Baseline | Replacement protection | Post-migration result | Manual regression | Difference and approval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BEH-S01 | Opening Search displays discovery results and the Discover projects title once data arrives. | `testFlow`, `testSearchLoaderIndicatorIsAnimating` | Confirmed | Passed, 67-test focused baseline | Retain assertions; add Feature success test | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Agent observed discovery cards and title on iPhone Air, iOS 26.2, 26 Oct | None |
| BEH-S02 | Changing the query immediately clears old cards and displays loading while the replacement request waits. | `testFlow`, `testCancelingOfSearchResultsWhenEnteringNewSearchTerms` | Confirmed | Passed, 67-test focused baseline | ViewModel presentation and Feature replacement tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | See bounded smoke checks below; remaining checks pending | None |
| BEH-S03 | Rapidly changing the query never lets an obsolete result replace the newest result. | `testCancelingOfSearchResultsWhenEnteringNewSearchTerms`, `testOrderingOfPopularAndDelayedSearches` | Confirmed | Passed, 67-test focused baseline | Controlled adverse-order completion and cancellation tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Network cancellation itself is not established by these tests |
| BEH-S04 | Clearing the query resets filters and sort and returns to discovery results; changing to another non-empty query retains filters. | `testClearSearchText_clearsFilters`, `testEmptySearchText_clearsFilters`, `testChangingSearchText_keepsOriginalFilters` | Confirmed | Passed, 67-test focused baseline | Existing presentation assertions plus direct Feature selection/reset tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | None |
| BEH-S05 | Changing a sort or filter reloads results for the new selection and keeps its visible selection consistent. | `test_flow_sort`, `test_flow_filterByCategory`; `SearchFiltersUseCaseTests` selection/reset cases | Confirmed | Passed, 67-test focused baseline | Feature selections and existing filter presentation tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | None |
| BEH-S06 | Reaching the pagination threshold appends subsequent results in order and stops when no next cursor exists. | `testFlow`; `PaginateTests.testPaginateFlow`, `testPagination_StopsWhenCursorIsNil`, interleaving cases | Confirmed | Passed, 67-test focused baseline | Feature cursor, overlap and replacement tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Current threshold is three remaining rows; repeated equivalent loads must share completion |
| BEH-S07 | A successful empty response displays the empty-result message; loading a new query hides it. | `testShowNoSearchResults` | Confirmed | Passed, 67-test focused baseline | Feature empty success and ViewModel empty/loading tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Empty success must remain distinct from failure |
| BEH-S08 | Selecting a card opens the same project/prelaunch destination with the appropriate first-card/query ref tag. | Four `testSearch…_RefTag` cases; controller route; existing framework prelaunch tests | Confirmed | Passed, 67-test focused baseline; framework snapshots not run | Keep route/ref-tag assertions | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | No new routing design |
| BEH-S09 | Search analytics distinguish page visits, completed queries and card clicks, without counting pagination or cancelled queries as completed searches. | `testProjectCardClicked`, `testSlowTyping`, page-view tests, `testFlow` | Confirmed | Passed, 67-test focused baseline | Preserve event values/counts through local tracking fake | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Production analytics not exercised | Demo startup intentionally disables external SDKs |
| BEH-S10 | Leaving and returning to Search retains its current results rather than automatically fetching more. | `testFlow`, `testSearchPageViewed_ReturningAfterSearching` | Confirmed | Passed, 67-test focused baseline | ViewModel lifecycle and Feature ownership tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Cancellation on disappearance must not discard completed results |
| BEH-S11 | The video-feed banner follows its feature flag and reachability, without repeated identical visibility events. | Three `testShowVideoFeedBanner…` cases | Confirmed | Passed, 67-test focused baseline | Preserve flag/reachability presentation tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Do not replace real flags with demo assumptions |
| BEH-S12 | A failed initial request stops loading, and a later changed query can recover. | New `testFailedInitialSearchStopsLoadingAndRecoversOnChangedQuery`; existing discarded error output | Confirmed by new baseline test | Passed, 67-test focused baseline | Feature retained error/retry test and presentation contract | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Silent error presentation is an existing defect candidate, not an approved final UX |

## Unresolved design and verification boundaries

- The current ViewModel has no error presentation for Feature failures. Preserve the distinction
  between an empty success and a failure in the new Feature. Do not invent a
  new error screen or claim that existing silence is the desired product UX.
- Existing names/comments describe "popular" discovery, but the filter
  implementation and its test default to `.magic`. Preserve actual tested
  selection; do not silently switch sort based on a comment.
- `viewWillAppearNotAnimated` currently filters `true`, despite its name.
  Preserve observed/tested lifecycle behaviour until explicitly resolved.
- Repeated filter reset emissions and debounce scheduling are observable in
  existing tests. Characterise their request and analytics effects before
  coalescing them; fewer calls alone is not proof of equivalence.
- Real-device timing, VoiceOver, logged-in filters, external APIs, all project
  destinations and snapshot comparisons remain separate validation gates.

## Bounded smoke checks after request extraction

On 26 October 2026, the agent observed discovery cards/title; Forest returning
three matches; a no-match query displaying the empty-state message; Cancel
restoring discovery; Newest selection showing its selected state; Paper Cities
opening the matching detail; and closing detail retaining Search cards/selection.
This supports parts of BEH-S01/S04/S05/S07/S08/S10, not every variant. No image
diff, rapid-typing timing measurement, complete filter journey, live API or
failure-UI test was performed. Newest ordering was not independently compared.

The Feature now retains errors separately from successful empty results. The
legacy ViewModel still has no new error presentation. Direct tests cover failed
first-page recovery, failed-page retry, cursor termination and obsolete
subscription completion suppression; they do not establish transport cancellation.

## Filter and async transport checkpoint (26 October 2026)

Historical checkpoint: this focused run passed 87 tests; the table now points
to the later native async checkpoint below. Three direct Feature tests now protect
BEH-S04/S05 query composition, reset-all retaining sort, empty-query resetting
sort, and toggle changes. The original presentation/analytics expectations remain
unchanged; a temporary analytics ordering regression was corrected in production
wiring before the filter commit (details in the ledger).

Ten additional tests protect Search's async transport and compatibility adapter:
exactly-once completion, cancellation before/during registration, cancellation
before invocation, GraphQL error precedence, nil/transport error mapping, mock
failure/recovery, Feature delivery, and query replacement cancelling its token
while ignoring late completion. This adds controlled transport evidence for
BEH-S03/S12, not a live-network or exhaustive async-screen verification claim.
Original baseline suites retain the legacy deterministic provider.

Fresh agent Simulator smoke on the async demo route observed discovery, Forest
returning three matches, Games narrowing to one, query clearing resetting category
and returning discovery, and the no-match message for Zzznomatch. This supports
BEH-S01/S04/S05/S07. No visual implementation changed; no pixel comparison was run.
Pagination/debounce, lookup cancellation and fully awaitable Feature commands
remain outstanding. Other manual gates in the table remain bounded as stated.
## Native awaitable pagination checkpoint (26 October 2026)

The current six-suite selection passes 93 tests. Existing ViewModel presentation,
navigation, lifecycle and analytics assertions now exercise the async provider and
native Feature execution, with a controlled result-delay clock rather than the
removed legacy provider. Three flow fixtures now install their service before
request admission; expectations were not weakened.

BEH-S02/S03/S06/S12 have direct adverse-order and retry coverage. Equivalent
in-flight first-page/page requests share one completion and append once. A new
query supersedes a pending page; its late completion cannot append or clear newer
loading. Explicit cancellation permits retry. Cancelled waiters do not cancel the
shared app-owned operation; they await its completion. Calls with no initial
query/next cursor are awaitable no-ops. Physical transport cancellation remains
covered by controlled callback/token tests, not live-network measurement.

Fresh agent smoke on the rebuilt Debug demo observed: Search discovery; scrolling
through later-page Edition 3 cards including Neighbourhood Sounds; query replacement
with Forest (three matches); Games (one match); clearing resets category/discovery;
Zzznomatch shows the existing no-results message; Solar Sketchbook detail opens and
closes back to Search. This supports BEH-S01/S04/S05/S06/S07/S08/S10 only for those
demo journeys. Pagination termination/repeated-load suppression is asserted in
tests, not inferred solely from a still screenshot. No pixel comparison, VoiceOver,
logged-in journey, error-UI injection or exhaustive destination check was run.

**Still incomplete:** category/location lookup execution and its races, remaining
reactive selection/presentation edges, full Search CFA review and broader validation.
Other app features remain outside this Search contract. Earlier checkpoint notes
about reactive pagination describe historical states, not the current implementation.
## Category/location lookup slice — automated verification passed

The initial baseline attempt was environment-blocked before compilation.
Matthew Thomas subsequently ran verify.zsh in Terminal. The agent inspected both
xcresult bundles: 114 tests passed (zero failures/skips), and the app build
succeeded. All 15 new tests passed. No fresh manual screen evidence is claimed.
See the ledger for paths, warning counts and runtime limitations.

| ID | Plain-English requirement | Legacy evidence | Evidence status | Baseline | Replacement protection | Post-migration result | Manual regression | Difference and approval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BEH-S13 | Opening filters reuses nonempty cached categories; an empty cache fetches, and a failed lookup can be retried. | FetchCategoriesUseCaseTests (three cases), existing KSCache key | Confirmed | Fresh run blocked before compilation | SearchLookupTests cache/failure/retry cases | Passed in 114-test run | Pending | Same cache and category delay; no new error UI |
| BEH-S14 | Default locations appear independently of category loading; location queries return suggestions and clearing immediately empties them. | FetchLocationsUseCaseTests (three cases), query limits 5/10 in source | Confirmed | Fresh run blocked before compilation | SearchLookupTests initial outputs, independent defaults and live fixture mapping | Passed in 114-test run | Pending | Native commands replace reactive execution |
| BEH-S15 | Clearing or replacing a location query prevents obsolete results and failures from changing the current suggestions or loading state. | Legacy empty-query branch bypasses switchMap cancellation; source-confirmed stale-response route | Confirmed user-requested correction | Source diagnosis; no runtime reproducer run | SearchLookupTests clear/late success, clear/late error, old/new ordering and cleanup tests | Passed in 114-test run | Pending | Intended approved change: user explicitly requested stale responses after clearing be addressed, 26 Oct 2026 |
| BEH-S16 | Failed nonempty location lookups retain existing suggestions; retry can recover, and whitespace remains a submitted query. | FetchLocationsUseCase materialize/values, nonempty filter | Inferred from source | Fresh run blocked | SearchLookupTests failure/retry, whitespace and cancelled-before-admission cases | Passed in 114-test run | Pending | Preserve silent UI errors; Feature retains errors separately |
| BEH-S17 | Equivalent pending lookups share one execution and completion; cancelling one waiter does not cancel another caller's shared request. | New explicit Feature overlap policy | Confirmed migration policy | Not an existing tested guarantee | SearchLookupTests shared query/options and cancelled waiter; SearchRequestCancellationTests location payload | Passed in 114-test run | Pending | Same policy as the preceding native Search pagination checkpoint |

No new visual design is authorized. Legacy and replacement lookup tests passed
together; remove the orphaned legacy location code only in a separately verified
cleanup. Manual filter smoke, whole-Search and whole-app completion remain open
at that checkpoint; see the subsequent bounded smoke below.

### Subsequent bounded filter smoke — 26 October 2026

Installed public demo, iPhone Air / iOS 26.2: category options loaded; Art
selection changed results and count; default locations appeared. Los returned
Los Angeles, clear removed the suggestion, and Port returned Portland.
Selecting Portland alongside Art showed the empty-results screen with two
filters. Reopening retained Portland's selected radio/text. Resetting location
restored results while preserving Art/count 1. Category Reset became disabled
after clearing its selection.

This covers the visible normal/clear/reopen/reset paths, not injected failures,
cache persistence, simultaneous waiter cancellation or forced late responses.
BEH-S14 has bounded manual confirmation; BEH-S15's race guarantee still relies
on controlled tests. Other automated-only checks remain so.
No screenshot regression, physical-device or live-API verification is claimed.

The orphan location implementation and its three tests have now been removed
from the working tree, recoverable from Git. These manual checks use the
pre-cleanup installed binary. Fresh cleanup build/tests remain blocked by
execution permissions (exit 74 before compilation), not passed.
Whole-Search and whole-app migration remain incomplete.

Post-cleanup follow-up confirmed 27 October 2026: the user-run Terminal check
in /private/tmp/kickstarter-search-lookup-cleanup.PQ3So7 passed all 111 tests
(zero failures/skips) and the app build. This supersedes the cleanup execution
blocker above. No Swift or project changes followed that successful run.
Manual smoke remains bounded to the pre-cleanup binary; broader validation
and the rest of the migration remain outstanding.

## Selection-state checkpoint — verification pending, 27 October 2026

Ordinary main-actor state replaces reactive filter storage. Direct Feature query
construction must be usable without subscriptions/initial signals, must not start
IO, and must preserve query text, every selected field, page size 15 and false
toggles represented as nil. New native API tests cover these requirements.

Compatibility requirements retained, inferred from current source:
the signal projection waits for initial selection; reset-all emits category,
state, percent, location, amount, goal, following, recommended, projects-we-love,
saved in that order, retaining sort. Clear resets sort last. Repeated identical
assignments still emit. New initial-barrier and ordered-emission tests protect
these details; they are not permission to redesign the UI or analytics.

Six new tests plus the 111-test baseline are pending runtime verification.
Syntax parsing passed but is not a type-check or test result. The build attempt
was sandbox-blocked before compilation. Earlier manual smoke does not validate
these newly changed files. Query/lifecycle and analytics adapters remain in use;
the overall migration is still in progress.

Follow-up verification on 27 October: all 123 focused tests passed and the app
built in `/private/tmp/kickstarter-search-selection-state.jLK7ZB`. This includes
the six selection-state tests and six adapter characterisation tests.
No production adapter changes preceded this result. The earlier pending status
is superseded for selection state only; UI/snapshot checks remain outstanding.

## Query/lifecycle adapter contract — 27 October 2026

| ID | Preserved requirement | Baseline protection | Status |
| --- | --- | --- | --- |
| SEARCH-ADAPTER-01 | Nonanimated appearance does not start discovery or track a page. First animated appearance initialises it once. | testNonAnimatedAppearanceDoesNotStartDiscoveryOrTrackPage | Confirmed by passing test; preserve existing animated flag semantics |
| SEARCH-ADAPTER-02 | Returning while loading retains the current request and tracks the latest query with the last published count. | testRepeatedAppearanceTracksWithoutReplacingInFlightRequest | Confirmed |
| SEARCH-ADAPTER-03 | First animated appearance replaces early text with discovery text without clearing filters. | testFirstAnimatedAppearanceReplacesEarlyQueryWithoutClearingFilters | Inferred intent, characterised and passing |
| SEARCH-ADAPTER-04 | Appearance before filter initialisation does not later backfill a page-view event. | testAppearanceBeforeLoadDoesNotBackfillPageView | Inferred intent, characterised and passing |
| SEARCH-ADAPTER-05 | Failed query adds no completion analytics; later appearance still tracks with retained count. | testFailedQueryDoesNotTrackCompletionButAppearanceStillTracks | Inferred error policy, characterised and passing |
| SEARCH-ADAPTER-06 | Card navigation preserves ref tags and click analytics include current query/filter parameters. | testCardClickAfterFilterChangeTracksCurrentParameters and existing ref-tag tests | Confirmed |

Post-change results for the upcoming adapter implementation are not yet available.

Adapter implementation now uses explicit input/lifecycle state and direct
appearance/card analytics. The six requirements above remain protected by the
same passing baseline tests; their post-change runtime results remain pending.
SEARCH-ADAPTER-07: reaching the final three rows requests a page once per threshold
crossing, including after a completed page; returning away from that threshold
allows a subsequent page. Protected by
testPaginationRequiresAnotherThresholdCrossingAfterPageCompletes (new, unverified)
and existing paging flow tests. No layout/navigation/copy changes intended.
Manual first appearance, return from detail, text/clear/filter changes, pagination
and banner checks remain required. Static parsing does not prove these outcomes.

Post-change verification confirmed 27 October 2026:
`/private/tmp/kickstarter-search-lifecycle-adapter.OvyAOX` contains 124 successful
tests with zero failures/skips and a successful app build. SEARCH-ADAPTER-01
through SEARCH-ADAPTER-07 therefore have passing focused post-change protection.
Manual UI and broader validation gaps above remain; migration is not complete.

## Completion analytics compatibility — pending verification, 27 October 2026

BEH-S09 describes the normal successful-page path. It is not a guarantee that
every pagination/error sequence emits no event: the legacy zero-count and
buffered-pairing behaviour below qualifies that wording. Do not silently fix
these potential analytics defects during an architecture-preserving migration.

| ID | Source-inferred legacy requirement | New protection | Status |
| --- | --- | --- | --- |
| SEARCH-ADAPTER-08 | Each empty non-discovery response emits zero-count analytics. | testEmptySearchesTrackZeroOncePerResponse | New test; runtime pending |
| SEARCH-ADAPTER-09 | Empty terminal pagination emits zero-count analytics while accumulated cards remain. | testEmptyTerminalPageTracksZeroWithoutDiscardingCards | New test; runtime pending |
| SEARCH-ADAPTER-10 | Unpaired empty/error settlements persist across queries; a later first-page ordinal may track before cards/loading=false publish. | testRecoveryAfterEmptyAndFailedQueriesPreservesAnalyticsPublicationTiming | New test; runtime pending |

The replacement explicitly owns the FIFO pairing and retains the independent
zero-count path. It uses current query/filter values when tracking, suppresses
discovery completion events, and does not change requests or UI. Three scenarios
are inferred from old source, not yet confirmed by differential runtime testing.
The 124-test/app-build baseline is acb105498d; that pass does not validate this
patch. The new 127-test check and app build await a Terminal run; local execution
was permission-blocked before compilation. No new manual/snapshot result.

Post-change follow-up: /private/tmp/kickstarter-search-completion-analytics.dVAhV6
contains 127 successful tests (zero failures/skips) and a successful app build.
SEARCH-ADAPTER-08 through -10 now have passing replacement protection. Their
legacy semantics remain source-inferred, not old-code differential confirmation.
No additional UI/snapshot/live-API/full-suite verification is claimed.

## Filter presentation lifetime — pending verification

- Lookup refresh/empty suggestions must replace option lists without clearing
  selected category/location or other filter values. Protected by
  testLookupRefreshAndClearPreserveSelectedFilters (new).
- Repeated lookup arrays must retain existing presentation notifications:
  testRepeatedLookupOutputsRetainPresentationNotifications (new).
- Observations belong to SearchFiltersUseCase. Releasing it detaches even if a
  caller retains SearchFilters: testReleasedAdapterStopsUpdatingRetainedPresentationModel
  (new owner-lifetime guarantee, not an active-screen behavioural redesign).
- Existing modal mapping, toggle/no-modal behaviour, logged-in/out pills, reset
  and selection tests remain unchanged. observeForUI scheduling remains.

Static checks passed; the 130-test runtime check and app build are pending.
No new UI layout, copy, storage, identifier or navigation changes.

Post-change confirmation: the Terminal run in
/private/tmp/kickstarter-filter-presentation.iBVlAx passed 130 tests with zero
failures/skips, including these three cases, and the app build. Both builds
report three warnings. Active-screen manual and snapshot validation remain open.

## Explicit query admission — runtime-unverified

SearchViewModel now owns per-screen input readiness and calls native Feature
parameter construction/admission explicitly. Selection policy, request lifetime
and cancellation still belong to SearchFeature.

| ID | Preserved requirement | Added regression protection |
| --- | --- | --- |
| SEARCH-QUERY-01 | Early query text waits for initial selection and then uses the current filters. | testEarlyQueryWaitsForInitialSelectionThenUsesCurrentFilters |
| SEARCH-QUERY-02 | Repeated load does not replace text or selected filters with discovery defaults. | testRepeatedLoadRetainsQueryAndSelection |
| SEARCH-QUERY-03 | A second screen using the shared Feature waits for its own selection publication before admitting a query. | testNewScreenWaitsForItsOwnSelectionPublication |

New tests are source-inferred, not runtime-confirmed. Reset-order and duplicate
request coverage now exercises SearchViewModel rather than the deleted legacy
signal-query overload. Parameter publication must precede admission/loading/cancellation;
query UI notification follows admission, and typed clear resets fields last.
Static parsing passed. The fresh 133-test/app-build attempt exited 74 before
compilation due to session permissions; no new runtime or manual pass claimed.

### Consolidated Search close-out

- `testFilterResetAdmitsRequestsInFieldOrderAndRetainsSort` protects the real
  screen-to-Feature reset route. Nine changed parameter sets admit requests;
  the unchanged nil-location notification shares the pending request.
- `testDuplicateFilterSharesPendingRequestButRefreshesAfterCompletion` protects
  equivalent in-flight sharing without swallowing a later intentional refresh.
- Initial-readiness coverage remains in SEARCH-QUERY-01 through -03. Native
  filter/query tests read ordinary Feature state without subscription setup.
- Remaining signals are UI compatibility: filter notifications/readiness,
  presentation projections, reachability/banner delivery and analytics pairing.
  They do not replace Feature-owned async request/pagination/lookup execution.
  Removing every reactive operator is not a Search exit requirement.
- Expected focused count remains 133 (two projection-only tests replaced by two
  live-route tests). This is a source count, not a recorded test pass.
- A direct Xcode escalation attempt was rejected by the session permission
  policy before execution. Runtime/type-check, strict-concurrency diagnostics
  and final manual/snapshot checks remain open. The current target uses Swift 5
  language mode; syntax parsing alone does not establish concurrency safety.

## Explore baseline preparation — no implementation change yet

Source review of DiscoveryViewModel and DiscoveryPageViewModel establishes these
requirements for the next complete feature, subject to baseline runtime checks:

- Four independently retained sort pages: Magic, Popular, Newest, Ending Soon.
  Page requests wait for user/parameters/visibility readiness. Returning without
  changed user/parameters does not imply a fresh request; pull-to-refresh,
  environment changes and blocked-user events explicitly refresh.
- Retain cards during refresh (`clearOnNewRequest: false`). Append distinct
  projects using the existing pagination URL, not Search's GraphQL cursor.
  Filter-change clearing and empty-state emission have separate ordering rules.
- Fetch an activity sample on signed-in appearance. Preserve seen-activity
  storage and the existing logout/navigation clearing rules and destinations.
- Preserve recommendation opt-in defaults, onboarding/personalisation flags,
  loading animations, playlist/ref-tag navigation and analytics timing.

One concrete DiscoveryFeature should own page-keyed collections and request
identities, constructed in AppModel; it must not share Search's collection or
cancel another sort page's work through one global request slot. Session and
seen-activity persistence retain their existing authoritative owners. Keep
existing controllers and presentation bindings. First validate the existing
DiscoveryViewModelTests and DiscoveryPageViewModelTests, then convert page and
sample requests as one integrated feature with cancellation/stale-result tests.
Both Discovery suites contain only logic/output assertions. Their existing
per-suite reference-simulator opt-out is now enabled (55 test methods); the
shared TestCase and all visual suites retain the reference-device guard. The
consolidated verification selects these alongside Search's expected 133 tests:
188 expected total, followed by the app build. This preparation is not a claim
that Explore is migrated or baseline-tested.


## Pledge mutation ownership — 28 October 2026

- Preserve create/update input fields: amount, reward/add-on identifiers, location,
  payment source, Apple Pay input, incremental mode, setup intent and create ref tag.
  Use the existing GraphQL input adapters and checkout/SCA response mappings.
- Preserve current cancellation wire behavior: backing ID is sent; the legacy
  client does not transmit its optional cancellation note. No new payload implied.
- Preserve reward-received REST route, project/backer IDs and Boolean value.
- PledgeFeature owns admitted writes independently of screen observation. Equivalent
  pending tails share; distinct commands execute in admission order within one
  account generation, including across create/update/cancel/received screens.
- Disposal/caller cancellation suppresses presentation but does not undo an admitted
  server write. Failed writes do not automatically retry or block later commands.
  This is local pending-request sharing, not a server idempotency guarantee.
- Account changes invalidate queued commands before admission and suppress old
  success/error delivery, including after artificial presentation delays. Already
  sent writes settle; a new generation has an independent command queue.
- Preserve existing loading/error/navigation, Apple Pay and SCA presentation,
  analytics and reward checkbox behavior. Public demo rejects all four writes.
- Original screen assertions remain; async test fixtures wait for owned operations
  before temporary environments end. Only the three nonvisual suites opt out of
  the reference-simulator gate. Real payments and visual/device parity remain open.


## Backing management and post-campaign checkout — 28 October 2026

- ManagePledge retains its REST project load followed by GraphQL rewards/payment-
  plan metadata, plus the separate backing query with increments, add-ons, refunds
  and expanded shipping rules. Keep the initial-project cache and backing refresh
  behavior, menu options, totals, payment display, banners and 300ms refresh animation.
- Feature-owned read routes share equivalent pending requests, supersede changed
  inputs and cancel on screen release/session changes. Screens have independent
  project/backing routes. A refresh waits for preceding writes and does not share
  a pre-write pending read. Completed reads are not cached by the Feature.
- The artificial API delay is applied once to the combined project response;
  formerly the project and rewards requests each applied it. Its production default
  remains zero. The actual sequential request dependencies and refresh animation
  remain; simulated latency is not a live-service performance measurement.
- PostCampaignCheckout creation, card/Apple Pay validation and completion use the
  same account-generation command owner as pledge mutations. Preserve amount,
  repeated reward IDs, location/ref tag, checkout-ID conversion, payment source,
  nullable reuse/Apple Pay fields and payment-intent secret. Never log these inputs.
- Validation retains the valid flag and server messages/error mapping. The complete
  mutation retains its raw GraphQL response contract, including existing downstream
  success/error interpretation. There is no automatic retry or server idempotency
  guarantee. Disposing observation does not undo an admitted financial write.
- Preserve existing Stripe authorization, checkout-terminated presentation, loading,
  button enablement, error/navigation and analytics bindings. This migration does
  not assert live Stripe, Apple Pay/3DS or server mutation verification.
- Existing checkout completion assertions now await the command. The old project-
  retry test omitted backing data; it now explicitly fails both reads and asserts
  two error/header events before a successful retry. Other business assertions are
  retained. Only the nonvisual ManagePledge suite newly opts out of the reference-
  simulator gate; visual/snapshot checks remain separate.


## Pledge-manager navigation and reward add-ons — 28 October 2026

| ID | Requirement | Baseline / protection | Scope limit |
| --- | --- | --- | --- |
| BEH-PM-01 | Opening a native update from pledge-manager loads its project and then its update; failures remain silent and never navigate with a partial pair. | 14 original PledgeManagerWebViewModel tests; new PledgeFeature paired-request, replacement, close and session tests. | Live web/server navigation remains unverified. |
| BEH-RA-01 | No-reward, missing reward and rewards without add-ons do not fetch add-ons; a successful nullable add-on response retains bonus-only behavior. | Original selection tests; Feature eligibility and nullable-result tests; native mock nil/empty/failure checks. | API fixture coverage does not prove live integration. |
| BEH-RA-02 | Preserve standard versus fast-query choice, reward ID, shipping location/country and country fallback. Preserve backed/unavailable, digital, local-pickup and shipping eligibility rules. | Original selection tests; Feature provider-input/fast-country cases and existing GraphQL mapper suite. | No product redesign or experiment-default change. |
| BEH-RA-03 | Preserve quantities, amounts, loading, pull-to-refresh error/retry, bonus support and continue navigation. | 15 original RewardAddOnSelectionViewModel tests; asynchronous completion awaited, business assertions retained. | Logic suite opts out of the snapshot reference-device gate; visual checks remain separate. |
| BEH-RA-04 | Replacing a request, releasing a screen or replacing its session prevents obsolete data/errors reaching the current screen. Equivalent pending reads share; explicit refresh after completion starts a new request. | Controlled noncooperative providers, cancelled-caller test and request/configuration coherence test. | Local sharing is not persistent caching or server idempotency. |

The unused RewardsUseCase enrollment helper had no application or test callers.
It is removed; the active ProjectDetailsFeature enrollment sequence and its tests
remain. Existing four login-gating tests remain intact. Add-on API delay now belongs
to the owned async task, so cancellation/account checks also cover that delay.
The display adapter retains each result's requesting project/reward/shipping data.

## Curated and post-backing recommendations — 28 October 2026

- Onboarding queries each selected category with live state and integer 30/category
  page budget, combines successful results, retains duplicates, and shuffles them.
  A failed category contributes no projects; an empty combined response displays
  the existing generic error. Empty category input performs no request/output.
- Thanks first loads the root category, then tries recommended (six), similar
  (three), and staff-picked category projects (three), in that order. Exclude the
  backed project, deduplicate by ID, and stop after three alternatives. A discovery
  failure allows the next source; a failed category or empty final list emits no
  recommendation section. Keep the existing recommended-list shuffle algorithm.
- Pair each list with its own category. Reconfiguration, route release and account
  replacement suppress obsolete results, including providers that ignore cancellation.
  Equivalent pending inputs on the same route share; independent screens do not
  cancel one another. Closing a screen cancels its pending recommendation reads.
- Preserve navigation/ref tags, newsletter settings ownership, analytics payloads,
  alerts, labels and layouts. Reactive outputs remain presentation adapters only.
- The 24 original CuratedProjects/Thanks logic tests passed before production edits.
  CuratedProjects alone newly opts out of the visual reference-device gate; no
  snapshot suite or global gate changes. Live recommendations remain unverified.

## Project attribution — 28 October 2026

Preserve one page-view mutation per ProjectPage instance, the current event name,
project graph ID and optional ref-info properties. Failure remains silent with no
automatic retry. The Feature owns admission; closing a page does not undo an event
already sent. An account change before dispatch rejects the obsolete event.
The native Apollo boundary retains cancellation/error handling. Existing unrelated
cold third-party advertising producers are not activated by this migration.

UpdateDraft's 29 original logic tests pass as the baseline for the next stage.
Only that nonvisual suite opts out of the reference-simulator gate; snapshot suites
retain their existing checks.

## Creator draft editing and images — 28 October 2026

- Preserve draft read, title/body/public fields, update number, focus/placeholder
  behavior, picker choices, error outputs, and Preview/Close destinations.
- CreatorDraftsFeature owns a native read route and a per-project/account command
  queue. Equivalent pending edits share; changed saves, uploads and deletions execute
  in admission order. A save uses the latest completed attachment state. Unchanged
  fields avoid an unnecessary server write. Failures permit an explicit later retry.
- Read replacement/release and account changes reject obsolete outcomes. Admitted
  writes settle after observation ends; account changes prevent queued dispatch.
  A save result retains its initiating action. Replaced save observation cannot
  trigger navigation for a newer action before that newer command completes.
- Correct attachment-state defects exposed by ownership: a later upload does not
  restore a deleted attachment; current attachments participate in Preview validation.
  Unsupported video deletion uses the existing failure output instead of trapping.
- REST paths, verbs, field names, authentication and response decoding remain.
  Image transport uses native URLSession async data, with multipart preparation
  off the UI actor, valid CRLF framing and errors for unreadable/empty/non-file input.
  Public demo rejects creator reads/writes rather than claiming live success.
- Baseline 29 original logic tests passed. They now await owned operations with
  original assertions retained. This retained model has no application constructor
  call found in the current checkout; actual editor reachability and device/image
  picker behavior are not established by these tests.

## Startup, navigation and creator blocking — 28 October 2026

Preserve config refresh triggers, visitor cookies, debug feature overrides, five-second
push debounce, Braze delivery, shortcut ordering/failure fallback, category matching,
and every existing deep-link controller stack. A resolved link is one operation:
project, optional update and optional replies must belong to the same destination.
A newer link (including a synchronous tab link), session change or delegate release
invalidates old navigation. Equivalent pending destinations share work.

Push registrations are admitted writes: equivalent pending tokens share; changed
tokens execute in order, without automatic retries. Stale account completions cannot
publish. Project creator blocking cooperates with the existing DiscussionFeature;
screen release only stops observation of an admitted block. Preserve success
notifications, errors and analytics. No screen design or live service action is part
of verification; use controlled providers and public demo fixtures.


## Developer pagination and rich-text examples — 29 October 2026

- Pagination first appearance requests default discovery parameters; pull-to-refresh
  uses staff picks/magic. Preserve rows while loading, append duplicates on the next
  page, stop at an empty page, and retain the original status/error strings. A failed
  page clears rows/cursor; an explicit refresh retries. Terminal next-page commands
  return immediately instead of waiting for a nonexistent publisher event.
- Rich-text list preserves order, nullable-node filtering, localized error text and
  nonempty caching when visiting a selected project and returning. Empty/error lists
  can retry. Accept the same raw owner/slug and project URL formats.
- Equivalent pending requests share within one screen route. Refresh replaces an
  old page; edited/cleared slug, screen suspension and session replacement reject late
  responses. Independent routes cannot cancel each other. No automatic write or live
  service verification. ViewModels are owned inline by their Views; request and cache
  policy belongs to DeveloperExamplesFeature composed in AppModel.
- All layout, text, navigation callbacks, colors and preview content are retained.
  Existing generic Paginator remains for other consumers; this example no longer uses
  its Combine request/next-event loop. Physical-device and visual parity remain gates.

### Pagination sentinel integration — 29 October 2026

A visible pagination row must re-evaluate after the initial page supplies rows,
and must disappear once the example reaches a terminal page. The waiter belongs
to the SwiftUI row; Feature owners coalesce repeated requests. Keep the existing
list, cell, status and spinner styling. The demo's first-six-row stall was observed
and corrected; one terminal-state regression and the shared PPO suites passed.

### Email-click redirects — 29 October 2026

Resolve the first HTTP redirect only, preserving default URLSession configuration
and existing silent failure/no-destination behavior. Never follow its target as
part of this resolution. A navigation route owns one current read: equivalent
pending URLs share, changed links supersede, ordinary new navigation and session
reset reject obsolete results. Deliver to the existing navigation input on MainActor.
The delegate only declines redirect following; it never touches UI or ViewModels.

### Root avatar — 29 October 2026

Preserve the cache-first tabbar-avatar-image hash filename, default URLSession
configuration, atomic best-effort cache write, existing circle/size/border rendering
and silent read failure. Cached bytes now arrive asynchronously, consistently with
downloaded bytes after tab styles are installed. A visible placeholder may therefore
appear briefly on a cache hit. Do not let a changed account/session, avatar URL,
logout or rebuilt tab index accept an obsolete image. The Profile Feature shares
equivalent pending reads; canceling a presentation waiter need not cancel a shared
cache fill. Logout/reset cancels the Feature read. Disk work runs on a storage actor.

## Permission/onboarding/configuration ownership — 29 October 2026

- PERMISSION-01: Preserve notification options and registration only on grant.
  Share equivalent pending prompts; serialize differing options. Observer cancellation
  suppresses delivery but never claims to retract admitted system consent.
- ONBOARDING-01: Keep pages, styling, navigation/analytics and already-authorized
  behavior. Appearance owns subscriptions; close/advance invalidates async completion.
  ATT keeps its existing authorization/ad-identifier updates.
- REMOTECONFIG-01: Keep public-demo guards, defaults, activation success/failure inputs
  and Crashlytics filtering. Retain/remove the SDK listener; realtime updates remain
  log-only. Share pending refreshes per client and reject replaced-client completion.
  An SDK activation already accepted may still change its cache.
- PERMISSION-02: Controlled tests do not prove physical-device consent UI or live
  Firebase behavior; those gates remain open.

## Video-feed player lifetime — 29 October 2026

- PLAYER-01: Keep the three-second startup/recovery policies, once-per-item failure,
  progress/watch counter calculations and existing scrub/loop UI. Repeated stalls
  share the first pending recovery window.
- PLAYER-02: Stop/reuse/release invalidate timers and per-item progress observation.
  Seek replacement, pause and stop reject obsolete completions. Current seek failure
  still reaches recovery UI; invalid-duration completion now arrives asynchronously.
- PLAYER-03: Platform notifications/periodic observations remain AVFoundation
  callbacks on their explicitly configured main queue; player/UI state is MainActor
  isolated. Controlled tests are not populated-video, audio hardware or visual proof.
