# Widget Setup in Xcode — Step by Step

## Step 1 — Add the Swift plugin to the app

1. In Xcode, open the Project navigator (left sidebar)
2. Expand **App → App**
3. Right-click the **App** folder → **Add Files to "App"**
4. Navigate to the `ios-widget/` folder in your project and select **LifePlugin.swift**
5. Make sure **Target: App** is ticked → click **Add**

## Step 2 — Register the plugin

1. Open **App/AppDelegate.swift**
2. Find the line that says `return super.application(...)` inside `application(_:didFinishLaunchingWithOptions:)`
3. Add this line ABOVE it:
   ```swift
   let _ = LifePlugin()
   ```

Actually, for Capacitor 6+ just adding the file is enough — it auto-registers via `@objc`.

## Step 3 — Add App Group to the main app

1. Click the **App** project (blue icon, top of sidebar)
2. Select the **App** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Search for **App Groups** and double-click it
6. Click the **+** button that appears
7. Type: `group.uk.co.prolineroofingandsolar.life`
8. Click **OK**

## Step 4 — Add the Widget Extension

1. Go to **File → New → Target**
2. Search for **Widget Extension** and select it → click **Next**
3. Fill in:
   - **Product Name:** `LifeTasksWidget`
   - **Include Configuration App Intent:** **OFF** (untick it)
4. Click **Finish**
5. When asked "Activate scheme?" click **Activate**

## Step 5 — Add App Group to the widget

1. In the project navigator, click the **App** project (blue icon)
2. Under **Targets**, select **LifeTasksWidget**
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability** → **App Groups**
5. Click **+** and add the same group: `group.uk.co.prolineroofingandsolar.life`

## Step 6 — Replace the widget code

1. In the project navigator, open **LifeTasksWidget → LifeTasksWidget.swift**
2. Select ALL the code (Cmd+A) and delete it
3. Open `ios-widget/LifeTasksWidget.swift` from this project
4. Copy ALL of it and paste into Xcode

## Step 7 — Build and run

1. Select your **iPhone** (or simulator) at the top
2. Make sure the scheme next to it says **App** (not LifeTasksWidget)
3. Press **▶ Play**

## Step 8 — Add the widget to your home screen

1. On your iPhone, long-press the home screen
2. Tap the **+** in the top corner
3. Search for **Life**
4. Choose small, medium, or large
5. Tap **Add Widget**

## Done!
The widget reads tasks automatically. It refreshes every 15 minutes,
and instantly when you add/complete a task in the app.
