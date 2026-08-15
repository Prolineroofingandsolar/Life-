# Privacy Policy — Life

**Last updated: [DATE OF PUBLICATION]**

> **To publish:** replace the bracketed placeholders below, then host this at a
> stable URL — `https://prolineroofingandsolar.co.uk/life/privacy` or similar.
> Apple requires a working privacy policy link for any app that reads Apple
> Health data, it must be live when you submit, and it must stay live for as
> long as the app is on the App Store.
>
> Every factual claim here was checked against the code, with one exception:
> **Settings ▸ Delete Account does not exist yet.** It is required by App Review
> guideline 5.1.1(v) and is being built; do not publish this policy until it
> ships, or the promise below is false on the day it is made.
>
> If the app changes, this changes with it — a policy that describes an older
> version is worse than none, because it is a promise you are no longer keeping.

---

Life is a personal productivity and health app. This policy explains what it
collects, where that goes, and what never leaves your phone.

The short version: **Life has no analytics, no advertising, no trackers, and no
third-party SDKs that profile you.** Your data is yours. It is stored on your
device, and — if you sign in — in a private area of our database that only your
account can read. The only time anything is sent to another company is when you
switch the AI coach on, and even then it is a small set of derived figures, not
your records.

## Who we are

Life is published by ProLine Roofing and Solar, [FULL REGISTERED COMPANY NAME],
[REGISTERED ADDRESS], United Kingdom.

For anything in this policy, contact **[CONTACT EMAIL ADDRESS]**.

## What Life collects

### Health data you choose to share

If you grant permission, Life reads the following from Apple Health:

| | |
|---|---|
| **Body** | body mass, body fat percentage, lean body mass, body mass index |
| **Activity** | step count, active energy burned, exercise time, walking and running distance, flights climbed |
| **Heart and recovery** | heart rate, resting heart rate, heart rate variability (SDNN), walking heart rate average, respiratory rate, blood oxygen, VO2 max, wrist temperature |
| **Sleep** | sleep analysis |

**Life never writes to Apple Health.** It only reads.

You can also connect Google or Fitbit as an alternative source for some of these
figures. If you do, the connection uses OAuth: Life receives access tokens,
which are stored in the iOS Keychain on your device and are never sent to us or
to anyone else.

Health permissions are optional. Declining them turns off the features that
depend on them; the rest of the app works.

### What you enter yourself

Tasks, habits, workouts and routines, weight and body measurements, water and
meal logs, direct debits and income, sleep notes, and your name if you give one.

### Progress photos

Progress photos are stored **on your device only**, in the app's own storage.
They are never uploaded, never included in the sync described below, and never
sent to us or anyone else. Deleting the app deletes them.

### Camera

If you use the gym-equipment scanner, Life takes one photo and sends it to be
identified (see *The AI coach* below). It is used once for that identification
and is not saved to your device, our systems, or your account. The camera is
used for nothing else, and the feature is off unless you turn it on.

### Your account

If you sign in, Life uses **Sign in with Apple** through Firebase
Authentication. We receive a user identifier and, depending on what you chose
when signing in, an email address — which may be one of Apple's private relay
addresses. We do not receive your Apple ID password or your Apple account
details.

Signing in is optional. Without it, Life works entirely on your device with no
sync.

### What Life does not collect

No analytics. No advertising identifiers. No crash-reporting SDK. No location
data. No contacts, no calendar, no photo library beyond images you explicitly
pick. Life does not track you across other apps or websites, and does not sell
or share your data for advertising.

## Where your data goes

### On your device

Everything, always. Life is fully usable without an account, and in that mode
nothing is transmitted anywhere.

### Sync, if you sign in

When you are signed in, Life stores a copy of your app data in Google Firebase
Firestore so it can appear on your other devices. It is written to an area
reserved for your account, and our database security rules permit only your own
signed-in account to read or write it. It contains your tasks, habits, workouts,
health figures and settings — the same things listed above, minus progress
photos, which never leave the device.

Firebase is provided by Google. Data is held on Google's infrastructure and
processed under Google's terms as our data processor.

### The AI coach

The coach is **off by default**, and it is useful without ever being turned on:
with AI disabled it runs entirely on rules inside the app and nothing is
transmitted.

If you enable it, you are shown a consent screen first that lists exactly what
is sent. Both the consent and the switch must be on before any data leaves the
device. When it is on, Life sends a small set of **derived figures** to Google's
Gemini model, through our own server:

- how long you slept and how that compares with your own recent baseline
- recovery described in words rather than raw measurements
- steps and active minutes against your goals
- whether a workout is planned
- counts of outstanding tasks and habits
- a note of anything missing or incomplete, so the coach can say it doesn't know
  rather than guess

**Never sent:** your name, your email, your account details, raw Apple Health or
Fitbit records, your provider access tokens, progress photos, or your notes.

**Task and habit names are not sent unless you separately switch that on.** They
are off by default because a task title routinely names a real person.

We use Gemini's **paid tier**, under which Google does not use submitted content
to train or improve their models.

Our server never stores the content of a coaching request. It records only
counts and estimated cost, so the app can show your usage and stop before a
spending limit. Its logs deliberately contain no health data and no prompt text.

The coach gives general wellbeing and fitness guidance generated by an AI model.
**It is not medical advice, not a diagnosis, and not a substitute for a
qualified professional.** Do not use it to make medical decisions.

## How long we keep it

Your data stays until you delete it. Deleting the app removes everything held on
that device. Deleting your account (see below) removes what is stored in
Firestore.

Usage and cost counters are kept per calendar month so the spending limit can be
enforced, and are removed with your account.

## Your rights

Under UK GDPR you may ask us to give you a copy of your data, correct it, delete
it, restrict how it is used, or object to its use. To exercise any of these,
contact **[CONTACT EMAIL ADDRESS]**.

Life is built so most of this needs no request at all:

- **Access and portability** — Settings ▸ Export exports everything as a JSON
  file you keep.
- **Erasure on the device** — Settings ▸ Reset All Data.
- **Erasure everywhere** — Settings ▸ Delete Account removes your account and
  the data stored against it. This cannot be undone.
- **Withdrawing consent** — Settings ▸ Coach ▸ Use AI. Health permissions are
  revocable at any time in the iOS Health app.

You also have the right to complain to the Information Commissioner's Office
(ICO) at [ico.org.uk](https://ico.org.uk).

## Our legal basis

We process this data on the basis of your **consent**, given when you grant
health permissions, sign in, or enable the coach. Health data is special
category data under UK GDPR, and we rely on your explicit consent for it. You
can withdraw consent at any time by the routes above.

## Children

Life is not intended for children under 13, and we do not knowingly collect
their data.

## Changes

If this policy changes materially we will update the date at the top and, where
the change affects how your data is used, tell you in the app.

## Contact

**[CONTACT EMAIL ADDRESS]**
ProLine Roofing and Solar, [REGISTERED ADDRESS]
