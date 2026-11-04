# Daily Budget

A private iPhone app for a 6-month budget (Nov 2026 – Apr 2027, $4,700). It shows how much you can spend today and lets you log every expense in a few taps. Dark iOS glass design, no backend: all data stays on the phone (SwiftData).

## Screens

- **Today**: money left today (ring), month left, next bill, today's expenses
- **Add expense** (+ button): amount, 12 categories (Food, Coffee, Transport, Sport, Skin care, Phone, Shopping, Health, Fun, Bills, Engagement, Other), note, date
- **History**: month total by category, each day marked under/over; tap a day to edit or delete
- **Plan**: $4,700 split, bills this month with paid checkmarks, month-by-month totals, CSV export

## Budget rules

1. Today's limit = living money left this month ÷ days left in the month. Unspent money rolls forward.
2. Everyday categories count against the $92/month living money. Bills and Engagement don't.
3. Living money left at the end of a month goes to emergency savings.

## Run it (needs a Mac)

1. Install Xcode from the Mac App Store (Xcode 26 or newer for the Liquid Glass look; Xcode 15+ works with a frosted fallback).
2. Install XcodeGen: `brew install xcodegen`
3. In this folder run: `xcodegen` — this creates `DailyBudget.xcodeproj`.
4. Open `DailyBudget.xcodeproj`, choose an iPhone simulator, press Run (⌘R). Run tests with ⌘U.

## Install on your iPhone

1. Xcode → Settings → Accounts → sign in with your Apple ID.
2. Select the DailyBudget target → Signing & Capabilities → Team = your Apple ID. If the bundle ID is taken, change `com.pensereyotdom19.dailybudget` to something unique.
3. iPhone: Settings → Privacy & Security → Developer Mode → On, then restart.
4. Connect the iPhone by cable, pick it as the run target, press Run.
5. iPhone: Settings → General → VPN & Device Management → trust your developer profile.

With a free Apple ID the app must be re-run from Xcode every 7 days. Your data is kept as long as you don't delete the app.

## Project layout

```
project.yml                 XcodeGen project definition
DailyBudget/
  DailyBudgetApp.swift      App entry, SwiftData container
  Models/                   Expense, Bill, BudgetSettings, Category, first-launch seed data
  Logic/                    BudgetCalculator (all budget math), MonthKey, Money
  Views/                    Today, Add expense, History, Plan, glass theme
DailyBudgetTests/           Unit tests for the budget math
```

## Next ideas

Home-screen widget, daily reminder notification, Khmer language, app icon.
