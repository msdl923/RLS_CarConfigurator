# Changelog

## 1.2.3 (2026-11-24)

**New**
- **Local brand stores:** stores that sell a single brand through a normal dealer lot also get the
  configurator, e.g. the "Online Dealerships" on RLS Italy (brand in the store's sub-filters, new-car
  mileage or "online" in the name). Settings: `detectLocalBrandStores`, `brandStoreMaxMileage`,
  `brandStoreNamePatterns`.
- **Equipment packages:** new step before paint. Take the wheels & tyres or the suspension of another
  trim of the same model line. Price = part value difference, downgrades refund 50 %. Only offered when
  both cars use the same slots. Combines with engine swaps.
- **Info sheet:** "i" button on models, trims, engine rows and the summary with the in-game
  description and a data sheet (power, torque, 0–100, top speed, weight, braking, off-road score …).
- **Comparison:** "⇄" adds up to three trims (also across models) to a side-by-side table with the
  best value highlighted.
- **Order overview:** "Orders" button with progress bar, remaining time and status (in production,
  ready for pickup, delivered). The store card shows open orders. Cars waiting for pickup can get a
  route or be delivered to a garage instead (garage delivery fee).
- **Dealer reputation bonus:** the configurator surcharge drops with the RLS reputation level of the
  dealer (level 2/3/4: −2/−4/−6 points). Setting: `reputationSurchargeReduction`.

**Fixes**
- RLS Italy online dealerships have no door on the map, so RLS blocked the checkout. During a
  configurator order such a store is treated as an online store (remote checkout, pickup at its
  parking spot); the original sales channel is restored afterwards. Setting: `localStoresAsOnline`.
- Store index is rebuilt per map (some store ids exist on several maps).
- Pickup message names the dealer for local stores.

## 1.0.0 (2026-11-10)

First public release.

- Configurator card in every RLS brand factory store (auto-detected per map)
- Model → body style → trim → engine → paint → delivery flow, English/German
- Current models only, incl. vehicle-mod configs; Cherrier FCV split into Vivace/Tograc/Ardente
- Trim categories (Petrol/Diesel/Electric/Other/Motorsport/Custom), sorting by price or power
- Limited runs (Tricolore, Rennspecht) listed with the regular trims
- Motorsport configs orderable with extra surcharge
- Engine swap incl. cross-model and petrol ↔ electric, donor filter, part-value pricing,
  donor gearbox/shifter/pedals/drive modes/gauges, base exhaust kept where possible
- Delivery tiers with delivery time; garage delivery or pickup at the dealer's freight point
- Resale value based on part value, surcharges not refunded
