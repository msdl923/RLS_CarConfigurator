<template>
  <div class="rlscfg-root">
    <!-- Entry card, placed as the first entry of the RLS vehicle list of this store. -->
    <Teleport v-if="available && hostReady" :to="cardHost">
      <div class="rlscfg-listcard" @click="openConfigurator">
        <div class="rlscfg-listcard-thumb">
          <img v-if="teaser.preview" :src="teaser.preview" alt="" @error="hideImg" />
          <span class="rlscfg-badge">{{ t("badge") }}</span>
        </div>
        <div class="rlscfg-listcard-body">
          <div class="rlscfg-listcard-title">{{ t("cardTitle") }}</div>
          <div class="rlscfg-listcard-sub">{{ shopName }} · {{ teaser.modelCount }} {{ t("models") }} · {{ teaser.configCount }} {{ t("configs") }}</div>
          <div class="rlscfg-listcard-models">{{ teaser.modelNames }}</div>
          <div v-if="teaser.openOrders" class="rlscfg-listcard-orders">{{ teaser.openOrders }} {{ teaser.openOrders === 1 ? t("orderOpenOne") : t("orderOpenMany") }}</div>
          <div class="rlscfg-listcard-foot">
            <span class="rlscfg-listcard-price">{{ t("from") }} {{ money(teaser.fromPrice) }}</span>
            <span class="rlscfg-listcard-btn">{{ t("configure") }} ›</span>
          </div>
        </div>
      </div>
    </Teleport>

    <div v-if="open" class="rlscfg-backdrop" @click.self="closeConfigurator">
      <div class="rlscfg-panel">
        <header class="rlscfg-header">
          <div>
            <div class="rlscfg-kicker">{{ shopName }}</div>
            <h2>{{ t("title") }}</h2>
          </div>
          <nav class="rlscfg-steps">
            <span v-for="(label, idx) in stepLabels" :key="idx" :class="{ active: stepIndex === idx, done: stepIndex > idx }">
              {{ idx + 1 }}. {{ label }}
            </span>
          </nav>
          <button class="rlscfg-btn ghost small" @click="openOrders">{{ t("orders") }}<span v-if="openOrderCount"> ({{ openOrderCount }})</span></button>
          <button class="rlscfg-close" @click="closeConfigurator">✕</button>
        </header>

        <div class="rlscfg-body">
          <div v-if="loading" class="rlscfg-info">{{ t("loading") }}</div>
          <div v-else-if="error" class="rlscfg-info rlscfg-error">{{ error }}</div>

          <!-- Step 1: model -->
          <div v-else-if="step === 'model'" class="rlscfg-grid">
            <div v-if="!catalog.models.length" class="rlscfg-info">{{ t("noModels") }}</div>
            <button v-for="model in catalog.models" :key="model.id || model.model_key" class="rlscfg-card" @click="selectModel(model)">
              <div class="rlscfg-thumb"><img v-if="model.preview" :src="model.preview" alt="" @error="hideImg" />
                <span v-if="model.description" class="rlscfg-info-btn" :title="t('infoTitle')" @click.stop="showModelInfo(model)">i</span>
              </div>
              <div class="rlscfg-card-title">{{ model.brand }} {{ model.name }}</div>
              <div class="rlscfg-card-sub">{{ model.configs.length }} {{ t("configs") }} · {{ t("from") }} {{ money(model.fromPrice) }}</div>
            </button>
          </div>

          <!-- Body style -->
          <div v-else-if="step === 'body'" class="rlscfg-grid">
            <button v-for="body in bodies" :key="body.name" class="rlscfg-card" @click="selectBody(body.name)">
              <div class="rlscfg-thumb"><img v-if="body.preview" :src="body.preview" alt="" @error="hideImg" /></div>
              <div class="rlscfg-card-title">{{ body.name }}</div>
              <div class="rlscfg-card-sub">{{ body.engineCount }} {{ t("engines") }} · {{ body.configs.length }} {{ t("configs") }}</div>
              <div class="rlscfg-card-price">{{ t("from") }} {{ money(body.fromPrice) }}</div>
            </button>
          </div>

          <!-- Engine (engine + power level), grouped by fuel category -->
          <div v-else-if="step === 'engine'" class="rlscfg-groups">
            <div class="rlscfg-toolbar">
              <span class="rlscfg-toolbar-label">{{ t("sortBy") }}</span>
              <button class="rlscfg-chip" :class="{ active: sortMode === 'price' }" @click="sortMode = 'price'">{{ t("sortPrice") }}</button>
              <button class="rlscfg-chip" :class="{ active: sortMode === 'power' }" @click="sortMode = 'power'">{{ t("sortPower") }}</button>
            </div>
            <section v-for="group in engineGroups" :key="group.id" class="rlscfg-section">
              <button class="rlscfg-section-head" @click="toggleGroup(group.id)">
                <span>{{ group.label }} <span class="rlscfg-count">{{ group.items.length }}</span></span>
                <span class="rlscfg-chevron">{{ isCollapsed(group.id) ? "▸" : "▾" }}</span>
              </button>
              <div v-if="!isCollapsed(group.id)" class="rlscfg-list">
                <button v-for="item in group.items" :key="item.key" class="rlscfg-row" :class="{ active: item.active }" @click="item.select()">
                  <div class="rlscfg-row-main">
                    <div class="rlscfg-card-title">{{ item.label }}<span v-if="item.power"> · {{ item.power }} {{ t("power") }}</span><span v-if="item.badge" class="rlscfg-tag">{{ item.badge }}</span><span v-if="item.cfg" class="rlscfg-info-btn inline" :title="t('infoTitle')" @click.stop="showInfo(item.cfg, item.model)">i</span><span v-if="item.cfg" class="rlscfg-compare-btn inline" :class="{ active: inCompare(item.cfg) }" :title="t('compareAdd')" @click.stop="toggleCompare(item.cfg, item.model)">⇄</span></div>
                    <div class="rlscfg-card-sub">{{ item.details }}</div>
                  </div>
                  <div class="rlscfg-row-side">
                    <div v-if="item.sub" class="rlscfg-card-sub">{{ item.sub }}</div>
                    <div class="rlscfg-card-price">{{ item.price }}</div>
                  </div>
                </button>
              </div>
            </section>
          </div>

          <!-- Variant: trim / transmission (in swap mode: trim of the base car) -->
          <div v-else-if="step === 'variant'" class="rlscfg-groups">
            <section v-for="group in variantGroups" :key="group.id" class="rlscfg-section">
              <button v-if="variantGroups.length > 1" class="rlscfg-section-head" @click="toggleGroup('v-' + group.id)">
                <span>{{ group.label }} <span class="rlscfg-count">{{ group.items.length }}</span></span>
                <span class="rlscfg-chevron">{{ isCollapsed('v-' + group.id) ? "▸" : "▾" }}</span>
              </button>
              <div v-if="!isCollapsed('v-' + group.id)" class="rlscfg-grid">
                <button v-for="cfg in group.items" :key="cfg.key" class="rlscfg-card" @click="selectConfig(cfg)">
                  <div class="rlscfg-thumb">
                    <img v-if="cfg.preview" :src="cfg.preview" alt="" @error="hideImg" />
                    <span v-if="cfg.configType && cfg.configType !== 'Factory'" class="rlscfg-badge">{{ cfg.configType }}</span>
                    <span class="rlscfg-info-btn" :title="t('infoTitle')" @click.stop="showInfo(cfg)">i</span>
                    <span class="rlscfg-compare-btn" :class="{ active: inCompare(cfg) }" :title="t('compareAdd')" @click.stop="toggleCompare(cfg)">⇄</span>
                  </div>
                  <div class="rlscfg-card-title">{{ cfg.name }}</div>
                  <div class="rlscfg-card-sub">{{ swapMode ? [cfg.engineLabel, cfg.power ? Math.round(cfg.power) + " " + t("power") : ""].filter(Boolean).join(" · ") : specLine(cfg) }}</div>
                  <div class="rlscfg-card-price">{{ swapMode ? t("from") + " " : "" }}{{ money(priceFor(cfg, defaultTier)) }}</div>
                </button>
              </div>
            </section>
          </div>

          <!-- Engine choice for swap-enabled models: factory engine or any compatible engine of the vehicle -->
          <div v-else-if="step === 'swapengine'" class="rlscfg-groups">
            <div class="rlscfg-swap-hint">{{ t("swapHint") }}</div>
            <div v-if="donorLines.length > 1" class="rlscfg-toolbar">
              <span class="rlscfg-toolbar-label">{{ t("donorFilter") }}</span>
              <button class="rlscfg-chip" :class="{ active: donorFilter === 'all' }" @click="donorFilter = 'all'">{{ t("all") }}</button>
              <button v-for="line in donorLines" :key="line.id" class="rlscfg-chip" :class="{ active: donorFilter === line.id }" @click="donorFilter = line.id">{{ line.name }}</button>
            </div>
            <div class="rlscfg-toolbar">
              <span class="rlscfg-toolbar-label">{{ t("sortBy") }}</span>
              <button class="rlscfg-chip" :class="{ active: sortMode === 'price' }" @click="sortMode = 'price'">{{ t("sortPrice") }}</button>
              <button class="rlscfg-chip" :class="{ active: sortMode === 'power' }" @click="sortMode = 'power'">{{ t("sortPower") }}</button>
            </div>
            <section v-for="group in swapGroups" :key="group.id" class="rlscfg-section">
              <button class="rlscfg-section-head" @click="toggleGroup(group.id)">
                <span>{{ group.label }} <span class="rlscfg-count">{{ group.items.length }}</span></span>
                <span class="rlscfg-chevron">{{ isCollapsed(group.id) ? "▸" : "▾" }}</span>
              </button>
              <div v-if="!isCollapsed(group.id)" class="rlscfg-list">
                <button v-for="item in group.items" :key="item.key" class="rlscfg-row" :class="{ active: item.active }" @click="item.select()">
                  <div class="rlscfg-row-main">
                    <div class="rlscfg-card-title">{{ item.label }}<span v-if="item.power"> · {{ item.power }} {{ t("power") }}</span><span v-if="item.badge" class="rlscfg-tag">{{ item.badge }}</span><span v-if="item.cfg" class="rlscfg-info-btn inline" :title="t('infoTitle')" @click.stop="showInfo(item.cfg, item.model)">i</span><span v-if="item.cfg" class="rlscfg-compare-btn inline" :class="{ active: inCompare(item.cfg) }" :title="t('compareAdd')" @click.stop="toggleCompare(item.cfg, item.model)">⇄</span></div>
                    <div class="rlscfg-card-sub">{{ item.details }}</div>
                  </div>
                  <div class="rlscfg-row-side">
                    <div v-if="item.sub" class="rlscfg-card-sub">{{ item.sub }}</div>
                    <div class="rlscfg-card-price">{{ item.price }}</div>
                  </div>
                </button>
              </div>
            </section>
          </div>

          <!-- Equipment packages: wheels / suspension of other variants of the same model line -->
          <div v-else-if="step === 'packages'" class="rlscfg-groups">
            <div class="rlscfg-swap-hint">{{ t("packagesHint") }}</div>
            <div v-if="!currentPackages" class="rlscfg-info">{{ t("loading") }}</div>
            <section v-for="cat in (currentPackages || [])" :key="cat.id" class="rlscfg-section">
              <div class="rlscfg-group-title">{{ cat.label }}</div>
              <div class="rlscfg-list">
                <button class="rlscfg-row" :class="{ active: !selectedPackages[cat.id] }" @click="choosePackage(cat.id, null)">
                  <div class="rlscfg-row-main">
                    <div class="rlscfg-card-title">{{ cat.currentLabel || t("packageStandard") }}<span class="rlscfg-tag">{{ t("packageStandard") }}</span></div>
                    <div class="rlscfg-card-sub">{{ selectedConfig.name }}</div>
                  </div>
                  <div class="rlscfg-row-side"><div class="rlscfg-card-price">±0</div></div>
                </button>
                <button v-for="opt in cat.options" :key="opt.donorKey" class="rlscfg-row"
                  :class="{ active: selectedPackages[cat.id] && selectedPackages[cat.id].donorKey === opt.donorKey }" @click="choosePackage(cat.id, opt)">
                  <div class="rlscfg-row-main">
                    <div class="rlscfg-card-title">{{ opt.label }}</div>
                    <div class="rlscfg-card-sub">{{ t("packageFrom") }} {{ opt.sourceName }}</div>
                  </div>
                  <div class="rlscfg-row-side"><div class="rlscfg-card-price">{{ signedMoney(opt.price) }}</div></div>
                </button>
              </div>
            </section>
          </div>

          <!-- Step 3: paint -->
          <div v-else-if="step === 'paint'" class="rlscfg-paint">
            <div class="rlscfg-paint-preview">
              <div class="rlscfg-thumb big"><img v-if="selectedConfig.preview" :src="selectedConfig.preview" alt="" @error="hideImg" /></div>
              <div class="rlscfg-swatch big" :style="{ background: selectedPaintColor }"></div>
              <div class="rlscfg-card-title">{{ selectedPaint ? prettyPaint(selectedPaint) : t("factoryPaint") }}</div>
            </div>
            <div class="rlscfg-swatches">
              <button v-for="paint in selectedModel.paints" :key="paint.name" class="rlscfg-swatch-btn"
                :class="{ active: paint.name === selectedPaint }" @click="selectedPaint = paint.name">
                <span class="rlscfg-swatch" :style="{ background: paint.color }"></span>
                <span class="rlscfg-swatch-name" :title="paint.name">{{ prettyPaint(paint.name) }}</span>
              </button>
              <div v-if="!selectedModel.paints.length" class="rlscfg-info">{{ t("noPaints") }}</div>
            </div>
          </div>

          <!-- Step 4: delivery + summary -->
          <div v-else-if="step === 'summary'" class="rlscfg-summary">
            <div class="rlscfg-summary-car">
              <div class="rlscfg-thumb big"><img v-if="selectedConfig.preview" :src="selectedConfig.preview" alt="" @error="hideImg" />
                <span class="rlscfg-info-btn" :title="t('infoTitle')" @click.stop="showInfo(selectedConfig)">i</span>
              </div>
              <div class="rlscfg-card-title">{{ selectedModel.brand }} {{ selectedModel.name }}</div>
              <div class="rlscfg-card-sub">{{ selectedConfig.name }} · {{ t("modelYear") }} {{ selectedConfig.year }}</div>
              <div class="rlscfg-card-sub">{{ [selectedConfig.bodyStyle, activePowertrain.engineLabel].filter(Boolean).join(" · ") }}<span v-if="selectedSwap" class="rlscfg-tag">{{ t("swapped") }}</span></div>
              <div class="rlscfg-card-sub">{{ specLine(activePowertrain) }}</div>
              <div v-for="pkg in chosenPackageList" :key="pkg.category" class="rlscfg-card-sub">{{ pkg.categoryLabel }}: {{ pkg.label }}</div>
              <div class="rlscfg-card-sub"><span class="rlscfg-swatch small" :style="{ background: selectedPaintColor }"></span> {{ selectedPaint ? prettyPaint(selectedPaint) : t("factoryPaint") }}</div>

            </div>
            <div class="rlscfg-summary-side">
              <h3>{{ t("delivery") }}</h3>
              <button v-for="tier in catalog.tiers" :key="tier.id" class="rlscfg-tier" :class="{ active: tier.id === selectedTier }" @click="selectedTier = tier.id">
                <span class="rlscfg-tier-head">
                  <b>{{ tier.label }}</b>
                  <span>{{ tier.durationText }}</span>
                </span>
                <span class="rlscfg-tier-desc">{{ tier.description }}<template v-if="tier.surchargePct"> · +{{ tier.surchargePct }} %</template></span>
              </button>
              <h3>{{ t("handover") }}</h3>
              <button class="rlscfg-tier" :class="{ active: fulfilment === 'garage' }" @click="fulfilment = 'garage'">
                <span class="rlscfg-tier-head"><b>{{ t("garageDelivery") }}</b><span>{{ money(garageFee) }}</span></span>
                <span class="rlscfg-tier-desc">{{ t("garageDeliveryDesc") }}</span>
              </button>
              <button class="rlscfg-tier" :class="{ active: fulfilment === 'pickup' }" @click="fulfilment = 'pickup'">
                <span class="rlscfg-tier-head"><b>{{ catalog.localStore ? t("pickupDealer") : t("pickup") }}</b><span>{{ t("free") }}</span></span>
                <span class="rlscfg-tier-desc">{{ catalog.localStore ? t("pickupDealerDesc") : t("pickupDesc") }}</span>
              </button>
              <div class="rlscfg-prices">
                <div><span>{{ t("newPrice") }}</span><span>{{ money(selectedConfig.basePrice) }}</span></div>
                <div><span>{{ t("badge") }} (+{{ catalog.surchargePct }} %)</span><span>{{ t("incl") }}</span></div>
                <div v-if="currentTier && currentTier.surchargePct"><span>{{ currentTier.label }} (+{{ currentTier.surchargePct }} %)</span><span>{{ t("incl") }}</span></div>
                <div v-if="selectedSwap"><span>{{ t("swapCost") }} (+{{ catalog.engineSwap.feePct }} % {{ t("swapFee") }})</span><span>{{ signedMoney(swapBase - selectedConfig.basePrice) }}</span></div>
                <div v-for="pkg in chosenPackageList" :key="'p-' + pkg.category"><span>{{ pkg.categoryLabel }}</span><span>{{ signedMoney(pkg.price) }}</span></div>
                <div v-if="catalog.reputation && catalog.reputation.reductionPct" class="bonus"><span>{{ t("repBonus") }} {{ catalog.reputation.level }} (−{{ catalog.reputation.reductionPct }} % {{ t("repBonusOn") }})</span><span>{{ t("incl") }}</span></div>
                <div v-if="currentExtraPct"><span>{{ t("motorsportSurcharge") }} (+{{ currentExtraPct }} %)</span><span>{{ t("incl") }}</span></div>
                <div v-if="fulfilment === 'garage'"><span>{{ t("garageDelivery") }}</span><span>{{ money(garageFee) }}</span></div>
                <div class="total"><span>{{ t("vehiclePrice") }}</span><span>{{ money(vehicleTotal) }}</span></div>
                <div class="hint">{{ t("checkoutHint") }}</div>
              </div>
            </div>
          </div>
        </div>

        <footer class="rlscfg-footer">
          <button v-if="history.length > 0" class="rlscfg-btn ghost" @click="back">{{ t("back") }}</button>
          <span class="rlscfg-spacer"></span>
          <span v-if="orderMessage" class="rlscfg-error">{{ orderMessage }}</span>
          <button v-if="compareList.length" class="rlscfg-btn ghost" @click="showCompare = true">{{ t("compare") }} ({{ compareList.length }})</button>
          <button v-if="step === 'packages'" class="rlscfg-btn" @click="goTo('paint')">{{ t("next") }}</button>
          <button v-if="step === 'paint'" class="rlscfg-btn" @click="goTo('summary')">{{ t("next") }}</button>
          <button v-if="step === 'summary'" class="rlscfg-btn primary" :disabled="ordering" @click="placeOrder">
            {{ ordering ? t("ordering") : t("checkout") }}
          </button>
        </footer>

        <!-- Info sheet: in-game description and performance data of a model / configuration -->
        <div v-if="infoItem" class="rlscfg-infopop-backdrop" @click.self="infoItem = null">
          <div class="rlscfg-infopop">
            <button class="rlscfg-close" @click="infoItem = null">✕</button>
            <div class="rlscfg-infopop-head">
              <div v-if="infoItem.preview" class="rlscfg-infopop-thumb"><img :src="infoItem.preview" alt="" @error="hideImg" /></div>
              <div>
                <div class="rlscfg-kicker">{{ infoItem.kicker }}</div>
                <h3>{{ infoItem.title }}</h3>
                <div class="rlscfg-card-sub">{{ infoItem.sub }}</div>
              </div>
            </div>
            <p class="rlscfg-infopop-desc">{{ infoItem.description || t("noDescription") }}</p>
            <div v-if="infoItem.specs.length" class="rlscfg-infopop-specs">
              <div v-for="spec in infoItem.specs" :key="spec.label"><span>{{ spec.label }}</span><b>{{ spec.value }}</b></div>
            </div>
          </div>
        </div>

        <!-- Comparison of up to three configurations -->
        <div v-if="showCompare" class="rlscfg-infopop-backdrop" @click.self="showCompare = false">
          <div class="rlscfg-infopop wide">
            <button class="rlscfg-close" @click="showCompare = false">✕</button>
            <h3>{{ t("compare") }}</h3>
            <div v-if="!compareList.length" class="rlscfg-info">{{ t("compareEmpty") }}</div>
            <table v-else class="rlscfg-compare">
              <thead>
                <tr>
                  <th></th>
                  <th v-for="entry in compareList" :key="entry.id">
                    <div class="rlscfg-compare-thumb"><img v-if="entry.cfg.preview" :src="entry.cfg.preview" alt="" @error="hideImg" /></div>
                    <div class="rlscfg-kicker">{{ entry.modelName }}</div>
                    <div>{{ entry.cfg.name }}</div>
                    <span class="rlscfg-compare-remove" @click="toggleCompare(entry.cfg, entry.model)">{{ t("compareRemove") }}</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in compareRows" :key="row.label">
                  <td>{{ row.label }}</td>
                  <td v-for="(value, idx) in row.values" :key="idx" :class="{ best: row.best === idx }">{{ value || "–" }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Order overview -->
        <div v-if="showOrders" class="rlscfg-infopop-backdrop" @click.self="closeOrders">
          <div class="rlscfg-infopop wide">
            <button class="rlscfg-close" @click="closeOrders">✕</button>
            <h3>{{ t("orders") }}</h3>
            <div v-if="ordersLoading" class="rlscfg-info">{{ t("loading") }}</div>
            <div v-else-if="!orders.length" class="rlscfg-info">{{ t("ordersEmpty") }}</div>
            <div v-else class="rlscfg-orders">
              <div v-for="order in orders" :key="order.inventoryId" class="rlscfg-order" :class="order.status">
                <div class="rlscfg-order-thumb"><img v-if="order.preview" :src="order.preview" alt="" @error="hideImg" /></div>
                <div class="rlscfg-order-main">
                  <div class="rlscfg-card-title">{{ order.name }}</div>
                  <div class="rlscfg-card-sub">{{ [order.config, order.engine].filter(Boolean).join(" · ") }}</div>
                  <div v-if="order.packages && order.packages.length" class="rlscfg-card-sub">{{ order.packages.join(" · ") }}</div>
                  <div class="rlscfg-card-sub">{{ order.sellerName }} · {{ order.tierLabel }} · {{ order.fulfilment === "pickup" ? t("pickupShort") : t("garageShort") }}</div>
                  <div class="rlscfg-order-bar"><div :style="{ width: Math.round((order.progress || 0) * 100) + '%' }"></div></div>
                </div>
                <div class="rlscfg-order-side">
                  <b>{{ orderStatusText(order) }}</b>
                  <span v-if="order.status === 'production'" class="rlscfg-card-sub">{{ t("remaining") }} {{ order.remainingText }}</span>
                  <span v-else-if="order.location" class="rlscfg-card-sub">{{ order.location }}</span>
                  <span class="rlscfg-card-sub">{{ money(order.price) }}</span>
                  <div v-if="order.status === 'pickup'" class="rlscfg-order-actions">
                    <button class="rlscfg-btn ghost small" @click="orderAction(order, 'route')">{{ t("orderRoute") }}</button>
                    <button class="rlscfg-btn ghost small" @click="orderAction(order, 'garage')">{{ t("orderToGarage") }}</button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from "vue"

const props = defineProps({ initial: { type: Object, default: null } })

// Two flows: models with engine swap pick the trim first and the engine afterwards (any engine of the
// vehicle); other models pick the engine first and then the matching factory variant.
const STEPS_FACTORY = ["model", "body", "engine", "variant", "packages", "paint", "summary"]
const STEPS_SWAP = ["model", "body", "variant", "swapengine", "packages", "paint", "summary"]

// Texts follow the game language (sent by Lua): German for "de", English otherwise.
const TEXT = {
  de: {
    badge: "Wunschkonfiguration", cardTitle: "Neuwagen nach Wunsch konfigurieren", models: "Modelle",
    configs: "Ausführungen", from: "ab", configure: "Konfigurieren", title: "Konfigurator",
    loading: "Katalog wird geladen…", noModels: "Keine aktuellen Modelle verfügbar.", factoryPaint: "Werkslack",
    noPaints: "Für dieses Modell sind keine Werkslacke hinterlegt.", modelYear: "Modelljahr", delivery: "Lieferung",
    newPrice: "Neupreis", incl: "inkl.", vehiclePrice: "Fahrzeugpreis",
    checkoutHint: "Steuern, Gebühren, Versicherung und Zustellung wählst du im nächsten Schritt im normalen Kaufmenü.",
    back: "Zurück", next: "Weiter", ordering: "Wird bestellt…", checkout: "Zum Kaufabschluss",
    orderFailed: "Bestellung fehlgeschlagen.", otherBody: "Weitere",
    stepModel: "Modell", stepConfig: "Ausführung", stepBody: "Karosserie", stepEngine: "Motorisierung",
    engines: "Motorisierungen", variant: "Ausführung", variants: "Ausführungen",
    swapEngine: "Motor tauschen", keepEngine: "Werksmotor behalten", swapped: "getauscht",
    factoryEngine: "Werksmotor", donorFilter: "Spender:", all: "Alle", sortBy: "Sortieren:", sortPrice: "Preis", sortPower: "Leistung",
    catPetrol: "Benzin", catDiesel: "Diesel", catElectric: "Elektro", catOther: "Sonstige", catCustom: "Custom / Tuning",
    catMotorsport: "Motorsport", motorsportSurcharge: "Motorsport-Aufschlag",
    handover: "Übergabe", garageDelivery: "Lieferung in die Garage", free: "kostenlos", pickup: "Abholung am Frachtpunkt",
    garageDeliveryDesc: "Nach der Lieferzeit steht das Auto in deiner Garage.",
    pickupDesc: "Nach der Lieferzeit steht das Auto am Frachtpunkt des Händlers bereit. Du bekommst eine Route.",
    stepTrim: "Ausstattung",
    swapCost: "Motortausch", swapFee: "Umbau",
    swapHint: "Behalte den Werksmotor oder baue einen anderen Motor dieses Fahrzeugs ein. Getriebe, Antrieb, Tank und Drehzahlmesser kommen passend mit.",
    noSwaps: "Für diese Ausführung gibt es keine anderen passenden Motoren.", stepPaint: "Farbe", stepDelivery: "Lieferung",
    power: "PS",
    holdOrder: "Halten zum Bestellen (Lieferung in Garage)", orderDelivery: "Bestellen (Lieferung in Garage)",
    deliveryNote: "Konfigurator-Bestellung: Nach der Lieferzeit wird das Fahrzeug direkt in deine Garage geliefert. Eine Abholung ist nicht nötig.",
    pickupDealer: "Abholung beim Händler",
    pickupDealerDesc: "Nach der Lieferzeit steht das Auto auf dem Parkplatz des Händlers bereit. Du bekommst eine Route.",
    infoTitle: "Beschreibung und Daten", noDescription: "Für diese Ausführung ist keine Beschreibung hinterlegt.",
    specPower: "Leistung", specTorque: "Drehmoment", specAccel: "0–100 km/h", specTop: "Höchstgeschwindigkeit",
    specWeight: "Gewicht", specWeightPower: "Leistungsgewicht", specDrive: "Antrieb", specGearbox: "Getriebe",
    specFuel: "Kraftstoff", specBrake: "Bremsweg 100–0", specOffroad: "Offroad-Wertung", specCountry: "Herkunft",
    specEngine: "Motor", specInduction: "Aufladung", seconds: "s",
    stepPackages: "Pakete", packagesHint: "Übernimm Felgen oder Fahrwerk aus einer anderen Ausführung dieses Modells. Berechnet wird nur der Wertunterschied der Teile.",
    packageStandard: "Serie", packageFrom: "aus", repBonus: "Händlerbonus Ruf-Level", repBonusOn: "auf Aufschlag",
    orders: "Bestellungen", ordersEmpty: "Noch keine Konfigurator-Bestellungen.", remaining: "noch",
    statusProduction: "In Produktion", statusPickup: "Abholbereit", statusDelivered: "Geliefert",
    pickupShort: "Abholung", garageShort: "Garage", orderOpenOne: "Bestellung unterwegs", orderOpenMany: "Bestellungen unterwegs",
    compare: "Vergleich", compareAdd: "Zum Vergleich hinzufügen", compareRemove: "entfernen", compareEmpty: "Noch nichts zum Vergleich ausgewählt.",
    orderRoute: "Route setzen", orderToGarage: "In Garage liefern",
    comparePrice: "Preis (Standard)", compareFull: "Maximal drei Ausführungen gleichzeitig.",
  },
  en: {
    badge: "Custom order", cardTitle: "Configure a new vehicle", models: "models",
    configs: "configurations", from: "from", configure: "Configure", title: "Configurator",
    loading: "Loading catalog…", noModels: "No current models available.", factoryPaint: "Factory paint",
    noPaints: "No factory paints are defined for this model.", modelYear: "Model year", delivery: "Delivery",
    newPrice: "Base price", incl: "incl.", vehiclePrice: "Vehicle price",
    checkoutHint: "Taxes, fees, insurance and delivery are chosen in the regular purchase menu next.",
    back: "Back", next: "Next", ordering: "Ordering…", checkout: "Continue to checkout",
    orderFailed: "Order failed.", otherBody: "Other",
    stepModel: "Model", stepConfig: "Variant", stepBody: "Body style", stepEngine: "Engine",
    engines: "engines", variant: "variant", variants: "variants",
    swapEngine: "Swap engine", keepEngine: "Keep factory engine", swapped: "swapped",
    factoryEngine: "Factory engine", donorFilter: "Donor:", all: "All", sortBy: "Sort:", sortPrice: "Price", sortPower: "Power",
    catPetrol: "Petrol", catDiesel: "Diesel", catElectric: "Electric", catOther: "Other", catCustom: "Custom / Tuning",
    catMotorsport: "Motorsport", motorsportSurcharge: "Motorsport surcharge",
    handover: "Hand-over", garageDelivery: "Delivery to garage", free: "free", pickup: "Pickup at freight point",
    garageDeliveryDesc: "After the delivery time the car is in your garage.",
    pickupDesc: "After the delivery time the car waits at the dealer's freight point. You get a route.",
    stepTrim: "Trim",
    swapCost: "Engine swap", swapFee: "conversion",
    swapHint: "Keep the factory engine or fit another engine of this vehicle. Transmission, drivetrain, fuel tank and tachometer come along.",
    noSwaps: "There are no other compatible engines for this variant.", stepPaint: "Paint", stepDelivery: "Delivery",
    power: "hp",
    holdOrder: "Hold to Order (Garage Delivery)", orderDelivery: "Order (Garage Delivery)",
    deliveryNote: "Configurator order: after the delivery time the vehicle is delivered straight to your garage. No pickup needed.",
    pickupDealer: "Pickup at the dealer",
    pickupDealerDesc: "After the delivery time the car waits on the dealer's lot. You get a route.",
    infoTitle: "Description and data", noDescription: "No description is available for this configuration.",
    specPower: "Power", specTorque: "Torque", specAccel: "0–60 mph", specTop: "Top speed",
    specWeight: "Weight", specWeightPower: "Power-to-weight", specDrive: "Drivetrain", specGearbox: "Transmission",
    specFuel: "Fuel", specBrake: "Braking 100–0 km/h", specOffroad: "Off-road score", specCountry: "Origin",
    specEngine: "Engine", specInduction: "Induction", seconds: "s",
    stepPackages: "Packages", packagesHint: "Take the wheels or suspension of another variant of this model. You only pay the value difference of the parts.",
    packageStandard: "Standard", packageFrom: "from", repBonus: "Dealer bonus, reputation level", repBonusOn: "on surcharge",
    orders: "Orders", ordersEmpty: "No configurator orders yet.", remaining: "",
    statusProduction: "In production", statusPickup: "Ready for pickup", statusDelivered: "Delivered",
    pickupShort: "Pickup", garageShort: "Garage", orderOpenOne: "order on its way", orderOpenMany: "orders on their way",
    compare: "Compare", compareAdd: "Add to comparison", compareRemove: "remove", compareEmpty: "Nothing selected for comparison yet.",
    orderRoute: "Set route", orderToGarage: "Deliver to garage",
    comparePrice: "Price (standard)", compareFull: "Up to three variants at a time.",
  },
}
const lang = ref("en")
function t(key) {
  const table = TEXT[lang.value] || TEXT.en
  return table[key] ?? TEXT.en[key] ?? key
}
const stepLabels = computed(() => swapMode.value
  ? [t("stepModel"), t("stepBody"), t("stepTrim"), t("stepEngine"), t("stepPackages"), t("stepPaint"), t("stepDelivery")]
  : [t("stepModel"), t("stepBody"), t("stepEngine"), t("stepConfig"), t("stepPackages"), t("stepPaint"), t("stepDelivery")])

const available = ref(false)
const sellerId = ref("")
const shopName = ref("")
const open = ref(false)
const loading = ref(false)
const error = ref("")
const catalog = ref({ models: [], tiers: [], surchargePct: 0 })
const step = ref("model")
const selectedModel = ref(null)
const selectedConfig = ref(null)
const selectedPaint = ref("")
const selectedTier = ref("")
const ordering = ref(false)
const orderMessage = ref("")
const teaser = ref({ modelCount: 0, configCount: 0, fromPrice: 0, preview: "", modelNames: "", openOrders: 0 })

// The list card lives in a host element that we keep as first child of RLS's ".vehicle-listings"
// (or in front of the "no vehicles" note). RLS re-renders that list, so a MutationObserver puts the
// host back whenever it gets moved or dropped.
const cardHost = document.createElement("div")
cardHost.className = "rlscfg-card-host"
const hostReady = ref(false)
let observer = null
let ensureQueued = false

function findAnchor() {
  const wrapper = document.querySelector(".vehicle-shop-wrapper")
  if (!wrapper) return null
  const listings = wrapper.querySelector(".main-content .vehicle-listings")
  if (listings) return { parent: listings, before: listings.firstChild }
  const empty = wrapper.querySelector(".main-content .branch .empty")
  if (empty && empty.parentNode) return { parent: empty.parentNode, before: empty }
  return null
}

function ensureHost() {
  ensureQueued = false
  if (!available.value) {
    if (cardHost.isConnected) cardHost.remove()
    hostReady.value = false
    return
  }
  const anchor = findAnchor()
  if (!anchor) {
    hostReady.value = cardHost.isConnected
    return
  }
  const inPlace = cardHost.parentNode === anchor.parent && (anchor.before === cardHost || cardHost.nextSibling === anchor.before)
  if (!inPlace) anchor.parent.insertBefore(cardHost, anchor.before === cardHost ? cardHost.nextSibling : anchor.before)
  hostReady.value = true
}

function queueEnsure() {
  if (ensureQueued) return
  ensureQueued = true
  window.requestAnimationFrame(ensureHost)
}

function startObserver() {
  if (observer) return
  observer = new MutationObserver(queueEnsure)
  observer.observe(document.body, { childList: true, subtree: true })
  queueEnsure()
}

function stopObserver() {
  if (observer) observer.disconnect()
  observer = null
  if (cardHost.isConnected) cardHost.remove()
  hostReady.value = false
}

const selectedBody = ref("")
const selectedEngine = ref("")
const history = ref([])
const selectedSwap = ref(null)       // donor config
const selectedSwapModel = ref("")    // donor model_key (may differ from the base model, e.g. K-Series -> 800)
const donorFilter = ref("all")
const swapQuotes = ref({})           // "baseModel/baseKey|donorModel/donorKey" -> {ok, basePrice}

// Engine parts that fit the selected model (own engines + compatible engines of other models in the shop).
const compatParts = computed(() => new Set(catalog.value.engineSwap?.compatible?.[selectedModel.value?.model_key] || []))
function recordId(record) { return record.id || record.model_key }
function quoteKey(baseCfg, baseModel, donorModel, donorCfg) {
  return `${baseModel}/${baseCfg.key}|${donorModel}/${donorCfg.key}`
}

// BeamNG reports EVs with fuel "Battery"; some mods use "Electric".
const isElectric = cfg => {
  const fuel = String(cfg?.fuel || "").toLowerCase()
  return fuel === "battery" || fuel.includes("electric")
}
// Swap flow only when the vehicle is enabled and more than one compatible engine exists.
const swapAvailable = computed(() => {
  const model = selectedModel.value
  if (!model || !(catalog.value.engineSwap?.models || []).includes(model.model_key)) return false
  const keys = new Set()
  for (const record of catalog.value.models || []) {
    for (const cfg of record.configs) {
      if (cfg.engineKey && compatParts.value.has(cfg.engineKey)) keys.add(engineKeyOf(cfg))
    }
  }
  return keys.size > 1
})
const swapMode = computed(() => swapAvailable.value)

// Categories for engine lists: custom/tuned configs separate, factory ones by fuel.
const CATEGORY_ORDER = ["petrol", "diesel", "electric", "other", "motorsport", "custom"]
function donorRank(cfg) {
  if (cfg && cfg.configType === "Factory") return 0
  return isFactoryLike(cfg) ? 1 : 2
}
function isFactoryLike(cfg) {
  if (!cfg) return false
  if (typeof cfg.factoryLike === "boolean") return cfg.factoryLike
  return !cfg.configType || cfg.configType === "Factory"
}
function categoryOf(cfg) {
  if (isMotorsport(cfg)) return "motorsport"
  if (cfg && !isFactoryLike(cfg)) return "custom"
  const fuel = String(cfg?.fuel || "").toLowerCase()
  if (fuel === "battery" || fuel.includes("electric")) return "electric"
  if (fuel.includes("diesel")) return "diesel"
  if (fuel.includes("gasoline") || fuel.includes("petrol") || fuel.includes("benzin")) return "petrol"
  return "other"
}
function categoryLabel(id) {
  return t({ petrol: "catPetrol", diesel: "catDiesel", electric: "catElectric", other: "catOther", motorsport: "catMotorsport", custom: "catCustom" }[id] || "catOther")
}

const sortMode = ref("price")
const collapsed = ref({ custom: true, "v-custom": true, motorsport: true, "v-motorsport": true })
function isCollapsed(id) { return collapsed.value[id] === true }
function toggleGroup(id) { collapsed.value = { ...collapsed.value, [id]: !isCollapsed(id) } }

function sortItems(items) {
  const byPrice = (a, b) => (a.sortPrice || 0) - (b.sortPrice || 0)
  const byPower = (a, b) => (a.power || 0) - (b.power || 0) || byPrice(a, b)
  return items.sort(sortMode.value === "power" ? byPower : byPrice)
}

// pinned: items shown in their own group on top (e.g. the factory engine).
function groupItems(items, pinned, pinnedLabel) {
  const groups = []
  if (pinned && pinned.length) groups.push({ id: "pinned", label: pinnedLabel, items: pinned })
  const map = new Map()
  for (const item of items) {
    const id = categoryOf(item.cfg)
    if (!map.has(id)) map.set(id, [])
    map.get(id).push(item)
  }
  for (const id of CATEGORY_ORDER) {
    if (map.has(id)) groups.push({ id, label: categoryLabel(id), items: sortItems(map.get(id)) })
  }
  return groups
}

const fulfilment = ref("garage")
// Must match garageDeliveryFeeFor() in core.lua (fee on the vehicle price incl. surcharges).
const garageFee = computed(() => {
  const f = catalog.value.fulfilment || {}
  const price = priceForBase(currentBase.value, currentTier.value, currentExtraPct.value)
  let fee = price * (Number(f.feePct) || 0) / 100
  fee = Math.max(Number(f.feeMin) || 0, fee)
  if (f.feeMax != null) fee = Math.min(Number(f.feeMax), fee)
  return Math.ceil(fee / 10) * 10
})
const vehicleTotal = computed(() =>
  priceForBase(currentBase.value, currentTier.value, currentExtraPct.value) + (fulfilment.value === "garage" ? garageFee.value : 0))
const currentExtraPct = computed(() => extraPct(selectedConfig.value, selectedSwap.value))
const activePowertrain = computed(() => selectedSwap.value || selectedConfig.value || {})
const currentBase = computed(() => swapBase.value + packagesTotal.value)
const swapBase = computed(() => {
  const base = selectedConfig.value
  if (!base) return 0
  if (!selectedSwap.value) return base.basePrice
  const quote = swapQuotes.value[quoteKey(base, selectedModel.value.model_key, selectedSwapModel.value, selectedSwap.value)]
  return quote && quote.ok ? quote.basePrice : base.basePrice
})

// Candidate donors: every config in the shop whose engine fits the base model (same model, other
// sub-models and other compatible models), one donor per engine + power level.
const swapCandidates = computed(() => {
  const base = selectedConfig.value
  if (!base || !swapAvailable.value) return []
  const baseModel = selectedModel.value.model_key
  const allowEnergy = catalog.value.engineSwap?.allowEnergyChange === true
  const groups = new Map()
  for (const record of catalog.value.models || []) {
    if (donorFilter.value !== "all" && recordId(record) !== donorFilter.value) continue
    for (const cfg of record.configs) {
      if (!cfg.engineKey || !compatParts.value.has(cfg.engineKey)) continue
      if (!cfg.engineSlot || cfg.engineSlot !== base.engineSlot) continue
      if (!allowEnergy && isElectric(cfg) !== isElectric(base)) continue
      const key = engineKeyOf(cfg)
      if (key === engineKeyOf(base)) continue
      if (!groups.has(key)) groups.set(key, [])
      groups.get(key).push({ cfg, record })
    }
  }
  const list = []
  for (const [key, entries] of groups) {
    // Donor preference: factory configs first (no mod/special parts), then the same sub-model, then the
    // same model, then the cheapest.
    entries.sort((a, b) =>
      donorRank(a.cfg) - donorRank(b.cfg) ||
      (a.record === selectedModel.value ? 0 : 1) - (b.record === selectedModel.value ? 0 : 1) ||
      (a.record.model_key === baseModel ? 0 : 1) - (b.record.model_key === baseModel ? 0 : 1) ||
      a.cfg.basePrice - b.cfg.basePrice)
    const { cfg: donor, record } = entries[0]
    list.push({
      key,
      donor,
      donorModel: record.model_key,
      donorLine: record.name,
      donorRecord: record,
      quoteKey: quoteKey(base, baseModel, record.model_key, donor),
      label: donor.engineLabel || donor.fuel || "",
      power: donor.power ? Math.round(donor.power) : null,
      details: [donor.fuel, donor.drivetrain, donor.transmission].filter(Boolean).join(" · "),
    })
  }
  return list
})

// Prices come from Lua (part values of the actually swapped parts); options Lua rejects are hidden.
const swapOptions = computed(() => swapCandidates.value
  .map(option => ({ ...option, quote: swapQuotes.value[option.quoteKey] }))
  .filter(option => !option.quote || option.quote.ok))

watch(swapCandidates, candidates => {
  const base = selectedConfig.value
  if (!base || !candidates.length) return
  const missing = candidates.filter(option => !swapQuotes.value[option.quoteKey])
  if (!missing.length) return
  const donors = missing.map(option => ({ model: option.donorModel, key: option.donor.key }))
  callLua("requestSwapQuotes", sellerId.value, selectedModel.value.model_key, base.key, JSON.stringify(donors))
})

// Donor filter chips: every model / sub-model line that provides at least one compatible engine.
const donorLines = computed(() => {
  const base = selectedConfig.value
  if (!base) return []
  const lines = []
  for (const record of catalog.value.models || []) {
    const provides = record.configs.some(cfg => cfg.engineKey && compatParts.value.has(cfg.engineKey)
      && cfg.engineSlot === base.engineSlot && engineKeyOf(cfg) !== engineKeyOf(base))
    if (provides) lines.push({ id: recordId(record), name: record.name })
  }
  return lines
})

function onSwapQuotes(payload) {
  const data = payloadObject(payload)
  if (!data || !data.quotes) return
  const next = { ...swapQuotes.value }
  for (const [donorRef, quote] of Object.entries(data.quotes)) {
    next[`${data.baseModel}/${data.baseKey}|${donorRef}`] = quote
  }
  swapQuotes.value = next
}

function chooseEngine(option) {
  selectedSwap.value = option ? option.donor : null
  selectedSwapModel.value = option ? option.donorModel : ""
  enterPackages(false)
}

function bodyOf(cfg) { return cfg.bodyStyle || t("otherBody") }
function engineKeyOf(cfg) { return `${cfg.engineLabel || ""}|${cfg.power ? Math.round(cfg.power) : ""}` }
function cheapest(configs) {
  return configs.reduce((min, cfg) => Math.min(min, priceFor(cfg, defaultTier.value)), Infinity)
}

const bodies = computed(() => {
  const map = new Map()
  for (const cfg of selectedModel.value?.configs || []) {
    const name = bodyOf(cfg)
    if (!map.has(name)) map.set(name, [])
    map.get(name).push(cfg)
  }
  return [...map.entries()].map(([name, configs]) => ({
    name,
    configs,
    preview: (configs.find(c => c.configType === "Factory" && c.preview) || configs.find(c => c.preview) || {}).preview,
    engineCount: new Set(configs.map(engineKeyOf)).size,
    fromPrice: cheapest(configs),
  }))
})

const bodyConfigs = computed(() => (selectedModel.value?.configs || []).filter(cfg => bodyOf(cfg) === selectedBody.value))

const engines = computed(() => {
  const map = new Map()
  for (const cfg of bodyConfigs.value) {
    const key = engineKeyOf(cfg)
    if (!map.has(key)) map.set(key, [])
    map.get(key).push(cfg)
  }
  const list = [...map.entries()].map(([key, configs]) => {
    const unique = values => [...new Set(values.filter(Boolean))].join(" / ")
    return {
      key,
      configs,
      label: configs[0].engineLabel || configs[0].fuel || "",
      power: configs[0].power ? Math.round(configs[0].power) : null,
      details: [unique(configs.map(c => c.fuel)), unique(configs.map(c => c.drivetrain)), unique(configs.map(c => c.transmission))]
        .filter(Boolean).join(" · "),
      fromPrice: cheapest(configs),
    }
  })
  return list.sort((a, b) => a.fromPrice - b.fromPrice)
})

const variants = computed(() => {
  const list = bodyConfigs.value.filter(cfg => engineKeyOf(cfg) === selectedEngine.value)
  return list.sort((a, b) => priceFor(a, defaultTier.value) - priceFor(b, defaultTier.value))
})

const engineGroups = computed(() => groupItems(engines.value.map(engine => ({
  key: engine.key,
  cfg: engine.configs[0],
  label: engine.label,
  power: engine.power,
  details: engine.details,
  sub: `${engine.configs.length} ${engine.configs.length === 1 ? t("variant") : t("variants")}`,
  price: `${t("from")} ${money(engine.fromPrice)}`,
  sortPrice: engine.fromPrice,
  select: () => selectEngine(engine.key),
}))))

const swapGroups = computed(() => {
  const base = selectedConfig.value
  if (!base) return []
  const factory = {
    key: "__factory",
    cfg: base,
    label: base.engineLabel || base.fuel || "",
    power: base.power ? Math.round(base.power) : null,
    details: [base.fuel, base.drivetrain, base.transmission].filter(Boolean).join(" · "),
    badge: t("factoryEngine"),
    price: "±0",
    sortPrice: 0,
    active: !selectedSwap.value,
    select: () => chooseEngine(null),
  }
  const others = swapOptions.value.map(option => ({
    key: option.key,
    cfg: option.donor,
    model: option.donorRecord,
    label: option.label,
    power: option.power,
    details: option.details,
    sub: `${t("from")} ${option.donorLine} · ${option.donor.name}`,
    price: option.quote ? signedMoney(option.quote.basePrice - base.basePrice) : "…",
    sortPrice: option.quote ? option.quote.basePrice : Number.MAX_SAFE_INTEGER,
    active: !!selectedSwap.value && selectedSwap.value === option.donor,
    select: () => chooseEngine(option),
  }))
  return groupItems(others, [factory], t("factoryEngine"))
})

// Swap flow: all trims of the body; factory flow: the variants of the chosen engine.
const variantGroups = computed(() => {
  const list = swapMode.value ? [...bodyConfigs.value] : [...variants.value]
  list.sort((a, b) => a.basePrice - b.basePrice)
  if (!swapMode.value) return [{ id: "all", label: "", items: list }]
  const map = new Map()
  for (const cfg of list) {
    const id = categoryOf(cfg)
    if (!map.has(id)) map.set(id, [])
    map.get(id).push(cfg)
  }
  return CATEGORY_ORDER.filter(id => map.has(id)).map(id => ({ id, label: categoryLabel(id), items: map.get(id) }))
})

// Mod / custom-config paints often carry technical names ("arsenic_pearl_v2"): make them readable.
function prettyPaint(name) {
  const text = String(name || "")
  if (/\s/.test(text) && !/_/.test(text)) return text
  return text
    .replace(/[_-]+/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, c => c.toUpperCase())
}

// Steps with exactly one option are skipped; history keeps "back" consistent with what was shown.
function goTo(next) {
  history.value.push(step.value)
  step.value = next
}

const stepIndex = computed(() => (swapMode.value ? STEPS_SWAP : STEPS_FACTORY).indexOf(step.value))
const defaultTier = computed(() => (catalog.value.tiers || []).find(t => t.id === catalog.value.defaultTier) || (catalog.value.tiers || [])[0])
const currentTier = computed(() => (catalog.value.tiers || []).find(t => t.id === selectedTier.value) || defaultTier.value)
const selectedPaintColor = computed(() => {
  const paint = (selectedModel.value?.paints || []).find(p => p.name === selectedPaint.value)
  return paint ? paint.color : "rgb(120,120,120)"
})

function payloadObject(payload) {
  if (Array.isArray(payload) && payload[0] && typeof payload[0] === "object") return payload[0]
  return payload && typeof payload === "object" ? payload : null
}

function luaQuote(value) {
  return String(value ?? "").replace(/\\/g, "\\\\").replace(/'/g, "\\'")
}

function engineLua(snippet) {
  const api = window.bngApi || window.beamng
  if (typeof api?.engineLua === "function") api.engineLua(snippet)
}

function callLua(fn, ...args) {
  const argList = args.map(a => `'${luaQuote(a)}'`).join(", ")
  engineLua(`if rlsConfigurator_core then rlsConfigurator_core.${fn}(${argList}) end`)
}

function money(value) {
  const n = Number(value) || 0
  return `$${Math.round(n).toLocaleString("de-DE")}`
}

// Must match isMotorsportConfig()/extraPctFor() in core.lua.
function isMotorsport(cfg) {
  const types = (catalog.value.motorsport?.types || []).map(x => String(x).toLowerCase())
  return !!cfg?.configType && types.includes(String(cfg.configType).toLowerCase())
}
function extraPct(cfg, donor) {
  return isMotorsport(cfg) || isMotorsport(donor) ? Number(catalog.value.motorsport?.surchargePct) || 0 : 0
}

function priceForBase(base, tier, extra = 0) {
  const pct = (Number(catalog.value.surchargePct) || 0) + (Number(tier?.surchargePct) || 0) + (Number(extra) || 0)
  return Math.ceil((base * (1 + pct / 100)) / 100) * 100
}

function priceFor(cfg, tier) {
  if (!cfg) return 0
  return priceForBase(cfg.basePrice, tier, extraPct(cfg))
}

function signedMoney(value) {
  const n = Math.round(Number(value) || 0)
  return (n >= 0 ? "+" : "−") + money(Math.abs(n))
}

function specLine(cfg) {
  if (!cfg) return ""
  const parts = []
  if (cfg.power) parts.push(`${Math.round(cfg.power)} ${t("power")}`)
  if (cfg.torque) parts.push(`${Math.round(cfg.torque)} Nm`)
  if (cfg.drivetrain) parts.push(cfg.drivetrain)
  if (cfg.transmission) parts.push(cfg.transmission)
  if (cfg.fuel) parts.push(cfg.fuel)
  return parts.join(" · ")
}

function hideImg(event) {
  if (event?.target) event.target.style.visibility = "hidden"
}

// Info sheet ----------------------------------------------------------------------------------------
const infoItem = ref(null)

// Lua translates descriptions already; key-like leftovers ("vehicles.x.y.description") are tried
// once more with the UI translator and hidden if they stay untranslated.
function readableText(text) {
  if (typeof text !== "string" || !text.trim()) return ""
  if (/\s/.test(text) || !text.includes(".")) return text
  try {
    const gp = window.bngVue?.app?.config?.globalProperties
    const fn = gp?.$t || gp?.$translate?.instant
    const value = typeof fn === "function" ? fn(text) : null
    if (typeof value === "string" && value && value !== text) return value
  } catch (_) {}
  return ""
}

function num(value) {
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}
function fmt(n, digits = 0) {
  return n.toLocaleString(lang.value === "de" ? "de-DE" : "en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits })
}

function specsFor(cfg) {
  const d = cfg?.details || {}
  const de = lang.value === "de"
  const specs = []
  const add = (labelKey, value) => { if (value !== null && value !== undefined && value !== "") specs.push({ label: t(labelKey), value }) }
  if (cfg.engineLabel) add("specEngine", cfg.engineLabel)
  const power = num(cfg.power)
  if (power) add("specPower", `${fmt(power)} ${t("power")}` + (d.powerRpm ? ` @ ${d.powerRpm} rpm` : ""))
  const torque = num(cfg.torque)
  if (torque) add("specTorque", `${fmt(torque)} Nm` + (d.torqueRpm ? ` @ ${d.torqueRpm} rpm` : ""))
  const accel = num(de ? d.accel100 : (d.accel60 ?? d.accel100))
  if (accel) add("specAccel", `${fmt(accel, 1)} ${t("seconds")}`)
  const top = num(d.topSpeed)
  if (top) add("specTop", de ? `${fmt(top * 3.6)} km/h` : `${fmt(top * 2.23694)} mph`)
  const weight = num(cfg.weight)
  if (weight) add("specWeight", de ? `${fmt(weight)} kg` : `${fmt(weight * 2.20462)} lb`)
  const wp = num(d.weightPower)
  if (wp) add("specWeightPower", `${fmt(wp, 2)} kg/${t("power")}`)
  add("specDrive", cfg.drivetrain)
  add("specGearbox", cfg.transmission)
  add("specFuel", cfg.fuel)
  if (d.induction) add("specInduction", d.induction)
  const brake = num(d.brake100)
  if (brake) add("specBrake", `${fmt(brake, 1)} m`)
  const offroad = num(d.offRoad)
  if (offroad !== null) add("specOffroad", `${fmt(offroad)} / 100`)
  if (d.country) add("specCountry", d.country)
  return specs
}

function showInfo(cfg, model) {
  if (!cfg) return
  const record = model || selectedModel.value || {}
  infoItem.value = {
    kicker: [record.brand, record.name].filter(Boolean).join(" "),
    title: cfg.name || cfg.key,
    sub: [cfg.year ? `${t("modelYear")} ${cfg.year}` : "", cfg.bodyStyle, cfg.configType].filter(Boolean).join(" · "),
    preview: cfg.preview || record.preview || "",
    description: readableText(cfg.details?.description) || readableText(record.description),
    specs: specsFor(cfg),
  }
}

function showModelInfo(model) {
  if (!model) return
  const years = (model.configs || []).map(c => c.year).filter(Boolean)
  infoItem.value = {
    kicker: model.brand || "",
    title: model.name,
    sub: `${(model.configs || []).length} ${t("configs")}` + (years.length ? ` · ${t("modelYear")} ${Math.max(...years)}` : ""),
    preview: model.preview || "",
    description: readableText(model.description),
    specs: [],
  }
}

function resetSelection() {
  infoItem.value = null
  showCompare.value = false
  selectedPackages.value = {}
  packageWaitingFor.value = ""
  step.value = "model"
  history.value = []
  selectedSwap.value = null
  selectedSwapModel.value = ""
  selectedBody.value = ""
  selectedEngine.value = ""
  selectedModel.value = null
  selectedConfig.value = null
  selectedPaint.value = ""
  selectedTier.value = ""
  orderMessage.value = ""
  ordering.value = false
}

function openConfigurator() {
  resetSelection()
  open.value = true
  loading.value = true
  error.value = ""
  callLua("requestCatalog", sellerId.value)
}

function closeConfigurator() {
  open.value = false
  ordering.value = false
  closeOrders()
}

function selectModel(model) {
  selectedModel.value = model
  selectedBody.value = ""
  selectedEngine.value = ""
  if (bodies.value.length === 1) return selectBody(bodies.value[0].name, true)
  goTo("body")
}

function selectBody(name, skipped) {
  if (skipped) history.value.push(step.value)
  selectedBody.value = name
  selectedEngine.value = ""
  if (swapMode.value) {
    if (bodyConfigs.value.length === 1) return selectConfig(bodyConfigs.value[0], true)
    if (skipped) step.value = "variant"
    else goTo("variant")
    return
  }
  if (engines.value.length === 1) return selectEngine(engines.value[0].key, true, skipped)
  if (skipped) step.value = "engine"
  else goTo("engine")
}

function selectEngine(key, skipped, alreadyPushed) {
  if (skipped && !alreadyPushed) history.value.push(step.value)
  selectedEngine.value = key
  if (variants.value.length === 1) return selectConfig(variants.value[0], skipped)
  if (skipped) step.value = "variant"
  else goTo("variant")
}

function selectConfig(cfg, skipped) {
  selectedConfig.value = cfg
  selectedSwap.value = null
  selectedSwapModel.value = ""
  donorFilter.value = "all"
  const paints = selectedModel.value?.paints || []
  const hasDefault = paints.some(p => p.name === cfg.defaultPaint)
  selectedPaint.value = hasDefault ? cfg.defaultPaint : (paints[0]?.name || "")
  selectedTier.value = catalog.value.defaultTier || (catalog.value.tiers || [])[0]?.id || ""
  selectedPackages.value = {}
  requestPackages(cfg)
  if (swapMode.value) {
    if (skipped) step.value = "swapengine"
    else goTo("swapengine")
    return
  }
  enterPackages(skipped)
}

function back() {
  orderMessage.value = ""
  const previous = history.value.pop()
  step.value = previous || "model"
}

function placeOrder() {
  if (!selectedModel.value || !selectedConfig.value) return
  ordering.value = true
  orderMessage.value = ""
  const packages = chosenPackageList.value.map(pkg => ({ category: pkg.category, donorKey: pkg.donorKey }))
  callLua("placeOrder", sellerId.value, selectedModel.value.model_key, selectedConfig.value.key, selectedPaint.value, selectedTier.value,
    selectedSwap.value ? selectedSwap.value.key : "", selectedSwap.value ? selectedSwapModel.value : "", fulfilment.value,
    packages.length ? JSON.stringify(packages) : "")
}

// Packages ------------------------------------------------------------------------------------------
const packageData = ref({})          // "recordId/configKey" -> [category, ...]
const selectedPackages = ref({})     // categoryId -> option
const packageWaitingFor = ref("")    // key whose answer decides whether the packages step is shown

function packageKey(cfg) { return `${selectedModel.value ? recordId(selectedModel.value) : ""}/${cfg ? cfg.key : ""}` }
const currentPackages = computed(() => packageData.value[packageKey(selectedConfig.value)] || null)
const chosenPackageList = computed(() => {
  const list = []
  for (const cat of currentPackages.value || []) {
    const opt = selectedPackages.value[cat.id]
    if (opt) list.push({ category: cat.id, categoryLabel: cat.label, donorKey: opt.donorKey, label: opt.label, price: Number(opt.price) || 0 })
  }
  return list
})
const packagesTotal = computed(() => chosenPackageList.value.reduce((sum, pkg) => sum + pkg.price, 0))

function requestPackages(cfg) {
  if (catalog.value.packagesEnabled === false || !cfg || !selectedModel.value) return
  if (packageData.value[packageKey(cfg)]) return
  callLua("requestPackages", sellerId.value, recordId(selectedModel.value), cfg.key)
}

// Shows the packages step when the selected variant has options, otherwise goes straight to paint.
function enterPackages(skipped) {
  const data = currentPackages.value
  if (catalog.value.packagesEnabled === false || (data && !data.length)) {
    if (skipped) step.value = "paint"
    else goTo("paint")
    return
  }
  packageWaitingFor.value = data ? "" : packageKey(selectedConfig.value)
  if (skipped) step.value = "packages"
  else goTo("packages")
}

function onPackages(payload) {
  const data = payloadObject(payload)
  if (!data || String(data.sellerId) !== String(sellerId.value)) return
  const key = `${data.recordId}/${data.key}`
  const categories = Array.isArray(data.categories) ? data.categories : []
  for (const cat of categories) cat.options = Array.isArray(cat.options) ? cat.options : []
  packageData.value = { ...packageData.value, [key]: categories }
  if (packageWaitingFor.value === key) {
    packageWaitingFor.value = ""
    if (!categories.length && step.value === "packages") step.value = "paint"
  }
}

function choosePackage(categoryId, option) {
  selectedPackages.value = { ...selectedPackages.value, [categoryId]: option || null }
}

// Comparison ----------------------------------------------------------------------------------------
const compareList = ref([])
const showCompare = ref(false)
function compareId(cfg, model) { return `${model ? recordId(model) : ""}/${cfg.key}` }
function inCompare(cfg) {
  return compareList.value.some(entry => entry.cfg === cfg || entry.cfg.key === cfg.key)
}
function toggleCompare(cfg, model) {
  const record = model || selectedModel.value
  const id = compareId(cfg, record)
  const index = compareList.value.findIndex(entry => entry.id === id)
  if (index >= 0) {
    compareList.value = compareList.value.filter((_, i) => i !== index)
    return
  }
  const next = [...compareList.value, { id, cfg, model: record, modelName: record ? `${record.brand || ""} ${record.name || ""}`.trim() : "" }]
  compareList.value = next.slice(-3)
}
const compareRows = computed(() => {
  const entries = compareList.value
  if (!entries.length) return []
  const labels = []
  const perEntry = entries.map(entry => {
    const map = {}
    for (const spec of specsFor(entry.cfg)) {
      map[spec.label] = spec.value
      if (!labels.includes(spec.label)) labels.push(spec.label)
    }
    return map
  })
  const priceRow = { label: t("comparePrice"), values: entries.map(entry => money(priceFor(entry.cfg, defaultTier.value))), best: -1 }
  const prices = entries.map(entry => priceFor(entry.cfg, defaultTier.value))
  priceRow.best = entries.length > 1 ? prices.indexOf(Math.min(...prices)) : -1
  const rows = [priceRow]
  // "best" marks the strongest value of numeric rows where higher (power) or lower (times, weight) wins.
  const lowerWins = new Set([t("specAccel"), t("specWeight"), t("specWeightPower"), t("specBrake")])
  const higherWins = new Set([t("specPower"), t("specTorque"), t("specTop"), t("specOffroad")])
  for (const label of labels) {
    const values = perEntry.map(map => map[label] ?? "")
    let best = -1
    if (entries.length > 1 && (lowerWins.has(label) || higherWins.has(label))) {
      const nums = values.map(v => parseFloat(lang.value === "de"
        ? String(v).replace(/\./g, "").replace(",", ".")
        : String(v).replace(/,/g, "")))
      const valid = nums.map((n, i) => [n, i]).filter(([n]) => Number.isFinite(n))
      if (valid.length > 1) {
        valid.sort((a, b) => lowerWins.has(label) ? a[0] - b[0] : b[0] - a[0])
        if (valid[0][0] !== valid[1][0]) best = valid[0][1]
      }
    }
    rows.push({ label, values, best })
  }
  return rows
})

// Orders --------------------------------------------------------------------------------------------
const showOrders = ref(false)
const orders = ref([])
const ordersLoading = ref(false)
const openOrderCount = ref(0)
let ordersTimer = null

function openOrders() {
  showOrders.value = true
  ordersLoading.value = orders.value.length === 0
  callLua("requestOrders")
  if (!ordersTimer) ordersTimer = window.setInterval(() => callLua("requestOrders"), 5000)
}
function closeOrders() {
  showOrders.value = false
  if (ordersTimer) window.clearInterval(ordersTimer)
  ordersTimer = null
}
function onOrders(payload) {
  const data = payloadObject(payload)
  if (!data) return
  ordersLoading.value = false
  orders.value = Array.isArray(data.orders) ? data.orders : []
  for (const order of orders.value) order.packages = Array.isArray(order.packages) ? order.packages : []
  openOrderCount.value = Number(data.openCount) || 0
}
function orderAction(order, action) {
  callLua("orderAction", String(order.inventoryId), action)
}
function orderStatusText(order) {
  return t({ production: "statusProduction", pickup: "statusPickup", delivered: "statusDelivered" }[order.status] || "statusDelivered")
}

function applyAvailability(data) {
  if (!data) return
  available.value = data.available === true
  if (data.lang) lang.value = data.lang === "de" ? "de" : "en"
  if (data.sellerId) sellerId.value = String(data.sellerId)
  if (data.shopName) shopName.value = data.shopName
  if (available.value) {
    teaser.value = {
      modelCount: data.modelCount || 0,
      configCount: data.configCount || 0,
      fromPrice: data.fromPrice || 0,
      preview: data.preview || "",
      modelNames: data.modelNames || "",
      openOrders: data.openOrders || 0,
    }
    openOrderCount.value = data.openOrders || 0
    startObserver()
  } else {
    open.value = false
    stopObserver()
  }
}

function onAvailability(payload) {
  applyAvailability(payloadObject(payload))
}

function onCatalog(payload) {
  const data = payloadObject(payload)
  if (!data || String(data.sellerId) !== String(sellerId.value)) return
  loading.value = false
  if (data.error) {
    error.value = data.error
    return
  }
  data.models = Array.isArray(data.models) ? data.models : []
  for (const model of data.models) {
    model.configs = Array.isArray(model.configs) ? model.configs : []
    model.paints = Array.isArray(model.paints) ? model.paints : []
  }
  data.tiers = Array.isArray(data.tiers) ? data.tiers : []
  if (data.lang) lang.value = data.lang === "de" ? "de" : "en"
  catalog.value = data
  packageData.value = {}
  fulfilment.value = data.fulfilment?.default === "pickup" ? "pickup" : "garage"
}

function onOrderResult(payload) {
  const data = payloadObject(payload)
  if (!data) return
  ordering.value = false
  if (data.ok) {
    open.value = false
    available.value = false
    stopObserver()
  } else {
    orderMessage.value = data.message || t("orderFailed")
  }
}

// RLS's purchase menu says "Order for Pickup" for brand stores below reputation level 2. Configurator
// orders are delivered to a garage instead, so relabel those texts while such an order is open.
let purchaseObserver = null
let relabelQueued = false

function relabelPurchaseTexts() {
  relabelQueued = false
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
  const hold = t("holdOrder"), order = t("orderDelivery"), note = t("deliveryNote")
  let node
  while ((node = walker.nextNode())) {
    const text = node.nodeValue
    if (!text) continue
    if (text.includes("Hold to Order for Pickup")) node.nodeValue = text.replace("Hold to Order for Pickup", hold)
    else if (text.includes("Order for Pickup")) node.nodeValue = text.replace("Order for Pickup", order)
    else if (text.includes("Freight pickup is required")) node.nodeValue = note
  }
}

function queueRelabel() {
  if (relabelQueued) return
  relabelQueued = true
  window.requestAnimationFrame(relabelPurchaseTexts)
}

function stopPurchaseObserver() {
  if (purchaseObserver) purchaseObserver.disconnect()
  purchaseObserver = null
}

function onPurchase(payload) {
  const data = payloadObject(payload)
  if (!data) return
  if (data.lang) lang.value = data.lang === "de" ? "de" : "en"
  stopPurchaseObserver()
  if (data.active && data.garageDelivery) {
    purchaseObserver = new MutationObserver(queueRelabel)
    purchaseObserver.observe(document.body, { childList: true, subtree: true, characterData: true })
    queueRelabel()
  }
}

function onKey(event) {
  if (open.value && (event.key === "Escape" || event.key === "Esc")) {
    event.stopPropagation()
    if (infoItem.value) infoItem.value = null
    else if (showCompare.value) showCompare.value = false
    else if (showOrders.value) closeOrders()
    else closeConfigurator()
  }
}

onMounted(() => {
  const bus = window.vueEventBus
  if (bus && typeof bus.on === "function") {
    bus.on("RlsConfiguratorAvailability", onAvailability)
    bus.on("RlsConfiguratorCatalog", onCatalog)
    bus.on("RlsConfiguratorOrderResult", onOrderResult)
    bus.on("RlsConfiguratorPurchase", onPurchase)
    bus.on("RlsConfiguratorSwapQuotes", onSwapQuotes)
    bus.on("RlsConfiguratorPackages", onPackages)
    bus.on("RlsConfiguratorOrders", onOrders)
  }
  window.addEventListener("keydown", onKey, true)
  applyAvailability(props.initial)
})

onBeforeUnmount(() => {
  const bus = window.vueEventBus
  if (bus && typeof bus.off === "function") {
    bus.off("RlsConfiguratorAvailability", onAvailability)
    bus.off("RlsConfiguratorCatalog", onCatalog)
    bus.off("RlsConfiguratorOrderResult", onOrderResult)
    bus.off("RlsConfiguratorPurchase", onPurchase)
    bus.off("RlsConfiguratorSwapQuotes", onSwapQuotes)
    bus.off("RlsConfiguratorPackages", onPackages)
    bus.off("RlsConfiguratorOrders", onOrders)
  }
  closeOrders()
  window.removeEventListener("keydown", onKey, true)
  stopObserver()
  stopPurchaseObserver()
})
</script>

<style scoped>
.rlscfg-root {
  font-family: inherit;
  color: #f2f2f2;
}
.rlscfg-card-host { display: block; }
.rlscfg-listcard {
  display: flex;
  gap: 1.2em;
  margin-bottom: 0.9em;
  padding: 0.6em;
  border-radius: 0.5em;
  background: linear-gradient(100deg, rgba(232, 67, 12, 0.22), rgba(30, 30, 33, 0.95) 45%);
  box-shadow: inset 0 0 0 1px rgba(255, 138, 61, 0.55);
  color: #f2f2f2;
  cursor: pointer;
}
.rlscfg-listcard:hover { box-shadow: inset 0 0 0 2px #ff8a3d; }
.rlscfg-listcard-thumb {
  position: relative;
  width: 17em;
  aspect-ratio: 16 / 9;
  flex-shrink: 0;
  border-radius: 0.35em;
  overflow: hidden;
  background: rgba(0, 0, 0, 0.35);
}
.rlscfg-listcard-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.rlscfg-badge {
  position: absolute;
  left: 0.5em;
  top: 0.5em;
  padding: 0.2em 0.55em;
  border-radius: 0.3em;
  background: #e8430c;
  font-size: 0.75em;
  font-weight: 700;
}
.rlscfg-listcard-body { flex: 1; display: flex; flex-direction: column; gap: 0.35em; min-width: 0; padding: 0.2em 0.4em 0.2em 0; }
.rlscfg-listcard-title { font-size: 1.35em; font-weight: 700; }
.rlscfg-listcard-sub { font-size: 0.9em; opacity: 0.75; }
.rlscfg-listcard-models { font-size: 0.9em; opacity: 0.6; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.rlscfg-listcard-foot { margin-top: auto; display: flex; align-items: center; justify-content: space-between; }
.rlscfg-listcard-price { font-size: 1.3em; font-weight: 700; color: #ffb347; }
.rlscfg-listcard-btn {
  padding: 0.45em 1em;
  border-radius: 0.35em;
  background: rgba(255, 255, 255, 0.1);
  font-weight: 700;
}
.rlscfg-listcard:hover .rlscfg-listcard-btn { background: #e8430c; }

.rlscfg-backdrop {
  position: fixed;
  inset: 0;
  z-index: 9001;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
}
.rlscfg-panel {
  display: flex;
  flex-direction: column;
  width: min(78rem, 92vw);
  height: min(48rem, 86vh);
  border-radius: 0.8em;
  background: rgba(22, 22, 25, 0.97);
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.07), 0 20px 60px rgba(0, 0, 0, 0.6);
  overflow: hidden;
}
.rlscfg-header {
  display: flex;
  align-items: center;
  gap: 1.5em;
  padding: 1em 1.4em;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}
.rlscfg-header h2 { margin: 0; font-size: 1.5em; }
.rlscfg-kicker { font-size: 0.8em; opacity: 0.6; text-transform: uppercase; letter-spacing: 0.06em; }
.rlscfg-steps { display: flex; gap: 1.2em; flex: 1; justify-content: center; font-size: 0.9em; }
.rlscfg-steps span { opacity: 0.4; }
.rlscfg-steps span.done { opacity: 0.7; }
.rlscfg-steps span.active { opacity: 1; color: #ff8a3d; font-weight: 700; }
.rlscfg-close {
  border: 0; background: transparent; color: #fff; font-size: 1.3em; cursor: pointer; opacity: 0.7;
}
.rlscfg-close:hover { opacity: 1; }

.rlscfg-body { flex: 1; overflow-y: auto; padding: 1.2em 1.4em; }
.rlscfg-info { opacity: 0.7; padding: 2em; text-align: center; }
.rlscfg-error { color: #ff7b6b; }

.rlscfg-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
  gap: 1em;
}
.rlscfg-card {
  display: flex;
  flex-direction: column;
  gap: 0.35em;
  padding: 0.7em;
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 0.6em;
  background: rgba(255, 255, 255, 0.04);
  color: inherit;
  text-align: left;
  cursor: pointer;
}
.rlscfg-card:hover { background: rgba(255, 255, 255, 0.09); border-color: rgba(255, 138, 61, 0.6); }
.rlscfg-groups { display: flex; flex-direction: column; gap: 1.4em; }
.rlscfg-list { display: flex; flex-direction: column; gap: 0.6em; }
.rlscfg-swap-hint { opacity: 0.75; font-size: 0.92em; }
.rlscfg-toolbar { display: flex; align-items: center; gap: 0.5em; }
.rlscfg-toolbar-label { opacity: 0.6; font-size: 0.9em; margin-right: 0.2em; }
.rlscfg-chip {
  padding: 0.3em 0.9em; border-radius: 1em; border: 0; cursor: pointer;
  background: rgba(255, 255, 255, 0.08); color: inherit; font-size: 0.9em;
}
.rlscfg-chip.active { background: #e8430c; font-weight: 700; }
.rlscfg-section { display: flex; flex-direction: column; gap: 0.6em; }
.rlscfg-section-head {
  display: flex; justify-content: space-between; align-items: center;
  padding: 0.5em 0.2em; border: 0; border-bottom: 1px solid rgba(255, 255, 255, 0.12);
  background: transparent; color: inherit; cursor: pointer; text-align: left;
  font-size: 1em; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em;
}
.rlscfg-count {
  margin-left: 0.4em; padding: 0.05em 0.5em; border-radius: 1em;
  background: rgba(255, 255, 255, 0.1); font-size: 0.8em; font-weight: 600;
}
.rlscfg-chevron { opacity: 0.6; }
.rlscfg-row.active { border-color: #ff8a3d; background: rgba(255, 138, 61, 0.12); }
.rlscfg-tag {
  margin-left: 0.5em; padding: 0.05em 0.45em; border-radius: 0.3em;
  background: #e8430c; color: #fff; font-size: 0.85em; font-weight: 700;
}
.rlscfg-row {
  display: flex; align-items: center; justify-content: space-between; gap: 1em;
  padding: 0.8em 1em; border-radius: 0.5em;
  border: 1px solid rgba(255, 255, 255, 0.06);
  background: rgba(255, 255, 255, 0.04);
  color: inherit; text-align: left; cursor: pointer;
}
.rlscfg-row:hover { background: rgba(255, 255, 255, 0.09); border-color: rgba(255, 138, 61, 0.6); }
.rlscfg-row-main { display: flex; flex-direction: column; gap: 0.3em; min-width: 0; }
.rlscfg-row-side { display: flex; flex-direction: column; align-items: flex-end; gap: 0.3em; flex-shrink: 0; }
.rlscfg-group-title { margin: 0 0 0.6em; font-size: 1.05em; opacity: 0.8; text-transform: uppercase; letter-spacing: 0.05em; }
.rlscfg-thumb {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  border-radius: 0.4em;
  background: rgba(0, 0, 0, 0.35);
  overflow: hidden;
}
.rlscfg-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.rlscfg-thumb.big { max-width: 34rem; }
.rlscfg-card-title { font-weight: 700; font-size: 1.05em; }
.rlscfg-card-sub { font-size: 0.85em; opacity: 0.7; display: flex; align-items: center; gap: 0.4em; }
.rlscfg-card-price { margin-top: auto; font-weight: 700; color: #ff8a3d; }

.rlscfg-paint { display: flex; gap: 2em; height: 100%; }
.rlscfg-paint-preview { display: flex; flex-direction: column; gap: 0.7em; width: 34rem; flex-shrink: 0; }
.rlscfg-swatches {
  flex: 1;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(9rem, 1fr));
  gap: 0.6em;
  align-content: start;
  overflow-y: auto;
}
.rlscfg-swatch-btn {
  display: flex; align-items: center; gap: 0.6em;
  padding: 0.5em; border-radius: 0.5em;
  border: 1px solid rgba(255, 255, 255, 0.06);
  background: rgba(255, 255, 255, 0.04);
  color: inherit; cursor: pointer; text-align: left;
}
.rlscfg-swatch-btn.active { border-color: #ff8a3d; background: rgba(255, 138, 61, 0.12); }
.rlscfg-swatch {
  display: inline-block;
  width: 1.8em; height: 1.8em;
  border-radius: 50%;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.25);
  flex-shrink: 0;
}
.rlscfg-swatch.big { width: 100%; height: 2.4em; border-radius: 0.4em; max-width: 34rem; }
.rlscfg-swatch.small { width: 1em; height: 1em; }
.rlscfg-swatch-name {
  font-size: 0.85em; min-width: 0; overflow: hidden; text-overflow: ellipsis;
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; line-height: 1.2;
}
.rlscfg-swatch-btn { min-width: 0; overflow: hidden; }

.rlscfg-summary { display: flex; gap: 2em; }
.rlscfg-summary-car { display: flex; flex-direction: column; gap: 0.5em; width: 34rem; flex-shrink: 0; }
.rlscfg-summary-side { flex: 1; display: flex; flex-direction: column; gap: 0.6em; }
.rlscfg-summary-side h3 { margin: 0 0 0.2em; }
.rlscfg-tier {
  display: flex; flex-direction: column; gap: 0.2em;
  padding: 0.7em 0.9em; border-radius: 0.5em;
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: rgba(255, 255, 255, 0.04);
  color: inherit; cursor: pointer; text-align: left;
}
.rlscfg-tier.active { border-color: #ff8a3d; background: rgba(255, 138, 61, 0.12); }
.rlscfg-tier-head { display: flex; justify-content: space-between; }
.rlscfg-tier-desc { font-size: 0.82em; opacity: 0.7; }
.rlscfg-prices { margin-top: 0.8em; display: flex; flex-direction: column; gap: 0.35em; }
.rlscfg-prices > div { display: flex; justify-content: space-between; font-size: 0.92em; }
.rlscfg-prices .total { margin-top: 0.4em; padding-top: 0.5em; border-top: 1px solid rgba(255, 255, 255, 0.12); font-size: 1.15em; font-weight: 700; }
.rlscfg-prices .hint { font-size: 0.78em; opacity: 0.55; display: block; }

.rlscfg-footer {
  display: flex; align-items: center; gap: 1em;
  padding: 0.9em 1.4em;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
}
.rlscfg-spacer { flex: 1; }
.rlscfg-btn {
  padding: 0.6em 1.4em; border-radius: 0.45em; border: 0;
  background: rgba(255, 255, 255, 0.12); color: #fff; cursor: pointer; font-size: 1em;
}
.rlscfg-btn:hover { background: rgba(255, 255, 255, 0.2); }
.rlscfg-btn.ghost { background: transparent; box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.2); }
.rlscfg-btn.primary { background: #e8430c; font-weight: 700; }
.rlscfg-btn.primary:hover { background: #ff5a1f; }
.rlscfg-btn:disabled { opacity: 0.5; cursor: default; }

/* Info button + sheet */
.rlscfg-info-btn {
  position: absolute;
  right: 0.45em;
  top: 0.45em;
  width: 1.6em;
  height: 1.6em;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.6);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.45);
  color: #fff;
  font-family: Georgia, serif;
  font-style: italic;
  font-weight: 700;
  font-size: 0.95em;
  cursor: pointer;
  z-index: 2;
}
.rlscfg-info-btn:hover { background: #e8430c; box-shadow: none; }
.rlscfg-info-btn.inline {
  position: static;
  display: inline-flex;
  vertical-align: middle;
  margin-left: 0.6em;
  width: 1.4em;
  height: 1.4em;
  font-size: 0.8em;
}
.rlscfg-infopop-backdrop {
  position: fixed;
  inset: 0;
  z-index: 9002;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.45);
}
.rlscfg-infopop {
  position: relative;
  width: min(40rem, 86vw);
  max-height: 80vh;
  overflow-y: auto;
  padding: 1.3em 1.5em 1.5em;
  border-radius: 0.7em;
  background: rgba(30, 30, 34, 0.99);
  box-shadow: 0 0 0 1px rgba(255, 138, 61, 0.45), 0 16px 50px rgba(0, 0, 0, 0.6);
}
.rlscfg-infopop > .rlscfg-close { position: absolute; right: 0.7em; top: 0.6em; }
.rlscfg-infopop-head { display: flex; gap: 1em; align-items: center; padding-right: 2em; }
.rlscfg-infopop-head h3 { margin: 0.1em 0 0.2em; font-size: 1.3em; }
.rlscfg-infopop-thumb { width: 11em; aspect-ratio: 16 / 9; flex-shrink: 0; border-radius: 0.35em; overflow: hidden; background: rgba(0, 0, 0, 0.35); }
.rlscfg-infopop-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.rlscfg-infopop-desc { margin: 1em 0; line-height: 1.45; opacity: 0.9; white-space: pre-line; }
.rlscfg-infopop-specs { display: grid; grid-template-columns: 1fr 1fr; gap: 0.35em 1.4em; font-size: 0.92em; }
.rlscfg-infopop-specs > div { display: flex; justify-content: space-between; gap: 1em; padding: 0.3em 0; border-bottom: 1px solid rgba(255, 255, 255, 0.07); }
.rlscfg-infopop-specs span { opacity: 0.65; }
.rlscfg-infopop-specs b { text-align: right; }

/* v1.2: orders, compare, packages, reputation */
.rlscfg-listcard-orders { font-size: 0.85em; color: #ffb347; }
.rlscfg-btn.small { padding: 0.35em 0.8em; font-size: 0.85em; }
.rlscfg-prices .bonus { color: #7fd17f; }
.rlscfg-compare-btn {
  position: absolute;
  right: 0.45em;
  top: 2.3em;
  width: 1.6em;
  height: 1.6em;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.6);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.45);
  color: #fff;
  font-size: 0.9em;
  cursor: pointer;
  z-index: 2;
}
.rlscfg-compare-btn.active, .rlscfg-compare-btn:hover { background: #e8430c; box-shadow: none; }
.rlscfg-compare-btn.inline {
  position: static;
  display: inline-flex;
  vertical-align: middle;
  margin-left: 0.4em;
  width: 1.4em;
  height: 1.4em;
  font-size: 0.8em;
}
.rlscfg-infopop.wide { width: min(64rem, 92vw); }
.rlscfg-infopop h3 { margin: 0 0 0.8em; }
.rlscfg-compare { width: 100%; border-collapse: collapse; font-size: 0.92em; }
.rlscfg-compare th { text-align: left; vertical-align: top; padding: 0 0.6em 0.8em; font-weight: 700; }
.rlscfg-compare td { padding: 0.35em 0.6em; border-bottom: 1px solid rgba(255, 255, 255, 0.07); }
.rlscfg-compare td:first-child { opacity: 0.65; white-space: nowrap; }
.rlscfg-compare td.best { color: #7fd17f; font-weight: 700; }
.rlscfg-compare-thumb { width: 100%; max-width: 14em; aspect-ratio: 16 / 9; border-radius: 0.35em; overflow: hidden; background: rgba(0, 0, 0, 0.35); margin-bottom: 0.4em; }
.rlscfg-compare-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.rlscfg-compare-remove { display: inline-block; margin-top: 0.3em; font-size: 0.8em; font-weight: 400; opacity: 0.6; cursor: pointer; text-decoration: underline; }
.rlscfg-compare-remove:hover { opacity: 1; color: #ff8a3d; }
.rlscfg-orders { display: flex; flex-direction: column; gap: 0.7em; }
.rlscfg-order { display: flex; gap: 1em; align-items: center; padding: 0.6em; border-radius: 0.45em; background: rgba(255, 255, 255, 0.05); }
.rlscfg-order.delivered { opacity: 0.6; }
.rlscfg-order-thumb { width: 9em; aspect-ratio: 16 / 9; flex-shrink: 0; border-radius: 0.35em; overflow: hidden; background: rgba(0, 0, 0, 0.35); }
.rlscfg-order-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.rlscfg-order-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 0.25em; }
.rlscfg-order-side { display: flex; flex-direction: column; align-items: flex-end; gap: 0.25em; flex-shrink: 0; }
.rlscfg-order.production .rlscfg-order-side b { color: #ffb347; }
.rlscfg-order.pickup .rlscfg-order-side b { color: #7fd17f; }
.rlscfg-order-bar { height: 0.35em; border-radius: 0.2em; background: rgba(255, 255, 255, 0.1); overflow: hidden; margin-top: 0.2em; }
.rlscfg-order-bar > div { height: 100%; background: #e8430c; }
.rlscfg-order.pickup .rlscfg-order-bar > div, .rlscfg-order.delivered .rlscfg-order-bar > div { background: #4caf50; }
.rlscfg-order-actions { display: flex; gap: 0.4em; margin-top: 0.3em; }
</style>
