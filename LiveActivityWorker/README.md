# N Link Live Activity Worker

A Cloudflare Worker that keeps N Link's charging Live Activity up to date.
While a charging Live Activity runs, the app registers its APNs device token
here; a cron trigger sends that device a silent background push every 5
minutes, and the app wakes, fetches the car's status from Hyundai/Kia itself,
and updates the Live Activity.

Only the push token, the activity type and timestamps are stored (in D1).
No vehicle or account data reaches the Worker. Registrations expire after 8
hours, and tokens APNs rejects are deleted.

## Routes

- `POST /wakeup` with `{ "pushToken", "activityType" }` (`charging` or `debug`)
- `POST /wakeup/unregister` with `{ "pushToken" }`

## Setup

1. Create an APNs key in your Apple Developer account (Keys → Apple Push
   Notifications service), topic-specific to the app's bundle ID. Put its Key
   ID, your Team ID and the bundle ID in `wrangler.toml`.
2. `npm install`, then `npx wrangler login`.
3. `npx wrangler d1 create nlink-live-activity` and put the printed
   `database_id` in `wrangler.toml`.
4. `npm run db:init` to create the table.
5. `npm run deploy`.
6. Add the `.p8` key as the `APNS_KEY` secret: in the Cloudflare dashboard
   (Workers & Pages → the Worker → Settings → Variables and Secrets), or with
   `npx wrangler secret put APNS_KEY < AuthKey_XXXXXXXXXX.p8`.
7. Set `BB_LIVE_ACTIVITY_HOST` in `Config/Shared.xcconfig` (or your
   `Config/Local.xcconfig`) to the Worker's host, without `https://`.

`APNS_HOST` must match how the app is signed: `api.sandbox.push.apple.com` for
builds installed from Xcode, `api.push.apple.com` for TestFlight and the App
Store.

## Local development

`npm run db:init:local`, then `npm run dev`. Put a throwaway key in
`.dev.vars` as `APNS_KEY="..."` (gitignored). The local runtime connects to
APNs over HTTP/1.1, which APNs rejects, so pushes only work once deployed.
`npm run tail` streams the deployed Worker's logs.
