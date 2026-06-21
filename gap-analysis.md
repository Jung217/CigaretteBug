# CigaretteBug × YoiLog — 差距分析與優先級 Backlog

> 對照靈感來源 **YoiLog**(ヨイログ)逐維度盤點現有 prototype,誠實版。
> 產出自多 agent 研究 + codebase 審查。日期:2026-06-21。

---

## 📍 實作進度(自走 /loop · 美術方向=可愛物件+深色舞台)

> 每輪保持 `flutter analyze` 乾淨、可 demo。

**Iteration 1(完成,analyze 乾淨)**
- ✅ **A1** 資料毀損止血:atomic write(temp+rename)、versioned wrapper、parse 失敗改備份 `.corrupt` 不再清空。`record_storage.dart`
- ✅ **A2** 效能:painter 改 repaint Listenable,停止每 frame 重建整樹;`_sync` 改 id-set diff。`physics_scene.dart`
- ✅ **B1** 全新渲染器:深色舞台漸層+聚光、圓潤卡片菸盒、真透視縮放(近大遠小)、高度感知陰影。刪掉假 3D 正交剪切 + 死碼 `scene_2d_view.dart`。
- ✅ **B2** 會滾:碰撞改 8 邊倒角多邊形 + `angularDamping` 2.5→0.35 + 初始角速度 → 傾斜會 tumble-roll。
- ✅ **B3** 材質:每面垂直漸層 + 玻璃光澤 rim light + 頂部高光 + 假厚度擠出;不再 lerp 到純黑(HSL 亮度地板 0.22)。
- ◐ **B4** juice:已加 pop-in 彈入動畫 + 記錄/抓取 haptic;**待做** 落地 squash、粒子、碰撞音效。
- ⬜ **B5** 老化:**待做** live 動畫(目前仍 spawn 時算一次)、配色再柔化。
- ➕ 順手:home cream 背景覆寫移除、空狀態提示、無標籤圓圈→高對比 amber 按鈕 + 醒目 + FAB、count 改 `今週 N 根` 標籤、修「空的時候按鈕最淡」bug。

**Iteration 2(完成,analyze 歸零)**
- ✅ **B5** 老化改 **live**:`_CigBody.aging` 改為 getter 每 frame 讀 `rec.agingProgress`,菸盒會隨時間在畫面上持續皺扁(不再只 spawn 算一次)。
- ✅ **B5** 配色柔化:`_cuteify()` 把刺眼原色壓飽和、抬亮度成糖果色,在深底上更可愛。
- ✅ **B4** 落地手感:接 forge2d `ContactListener.postSolve` → 依衝量觸發壓扁回彈(`squash`)+ 塵土粒子噴發 + 節流 `HapticFeedback`(回調內只改 Dart 物件,符合 forge2d 限制)。
- ✅ 順手清掉全部 5 個既有 deprecation(`withOpacity`→`withValues`、Switch `activeColor`→`activeThumbColor`)→ **`flutter analyze` 0 issues**。

**Iteration 3(完成,analyze 0 issues)**
- ✅ **重構** `app_providers`:抽出 `periodBounds()` + `recordsForPeriod()` 共用函式,`filteredRecordsProvider` 行為不變但邊界改 `[start, end)`(含起點)。
- ✅ **D2** stats 全面期間化:加 日/週/月/年 切換器 + 前後期導航(擋未來);四張卡片全部讀**當期**資料;**真趨勢圖**(日→逐時、週→逐日、月→逐日、年→逐月,fl_chart BarChart);**本期 vs 上一期 delta 卡**(少=綠 trending_down、多=紅 trending_up,非說教式可見度提醒)。
- ✅ **D2** 修花費:改累加 `packPrice/packSize` 最後才 round(不再逐根四捨五入),標示「約」。
- ✅ 刪死碼 `stats_header.dart`(home 已有 count chip 取代)。

**Iteration 4(完成,analyze 0 issues)**
- ✅ **D1** 底部 NavigationBar:`HomeScreen` 重構成 4 分頁 scaffold(首頁/統計/圖鑑/設定 + `IndexedStack`),物理場景 full-bleed 在後。移除浮在場景上、會被菸盒蓋住的 4 個無標籤圓圈(stats/settings/calendar/collection)+ 無用的 `_btn` helper + 3 個無用 import。home 保留 count chip(切期間)、空狀態、+ FAB。

**待續(多為需你拍板的產品分岔或需實機驗證的視覺)**:
- Phase C1 **pile 持久累積**:⚠️ 產品分岔 —— 首頁堆疊要改成「持久成長的收藏」(YoiLog 式,期間篩選只留給 stats),還是維持現在「反映所選期間」?會改變 home count chip 語意,且需要 live body 上限避免效能爆掉。**建議等你決定**。
- Phase C3 圖鑑變 dex:用新的可愛菸盒樣式重繪、首次解鎖動畫(視覺,需實機校正)。
- 倫理方向(慶祝消費 vs 推向少抽)仍未拍板 → 影響 C 的獎勵設計。
- scanner 死碼(重啟 mobile_scanner / 誠實標示)、group 死碼(接上或刪)。

**Iteration 5(完成,analyze 0 issues)**
- ✅ **C3** 圖鑑 dex 重繪:抽出共用 `lib/utils/pack_palette.dart`(`cuteify`/`packShade`);收藏頁用 `PackThumbPainter` 畫圓潤糖果菸盒(漸層+rim+假厚度),取代平色方塊;未解鎖=深色剪影+鎖;點擊看品牌詳情(焦油/尼古丁/價格/收集數);卡片 `easeOutBack` 浮現動畫;加熱菸標記。
- 註:physics_scene 仍保留自己的 `_cuteify`/`_shift`(與 util 重複,未來可收斂),為避免動到你正在跑的核心檔暫不重構。

---

## 🔄 重大轉向:2.5D → 真 3D(2026-06-21)

使用者實機跑過後拒絕了我做的 2.5D 圓角卡片(「這不是我要的 我要 3D」)。我抓 YoiLog App Store 實際截圖用視覺確認:它是**真 3D 圓柱罐子/瓶子**(曲面/頂蓋/柔光/AO,淺色背景)。

**使用者拍板的修正方向**:① 先自寫真 3D 軟體渲染器(無需素材,滿意再上引擎)② 維持深色舞台 ③ 主體=菸盒立方體+散落圓柱菸/煙蒂。詳見記憶 [[art-direction-decision]]。

**Iteration 6(完成,analyze 0 issues)— 真 3D 渲染器**
- ✅ `physics_scene.dart` 整個重寫成「傾斜相機地面視角」軟體 3D:
  - **菸盒**=透視 3D 立方體(8 頂點、6 面、逐面 Lambert 打光、頂/側可見、面 depth-sort、頂面印品牌名)
  - **香菸**=曲面漸層 3D 圓柱(16 段環、逐段曲面打光、近端濾嘴蓋),`angularDamping` 極低 → 會自轉/滾
  - 每筆記錄 spawn 1 菸盒 + 1 香菸;深色舞台 + 接觸陰影 + pop-in + 落地 squash/粒子/haptic + live 老化
  - 相機/光源常數在檔頂可調(`_camElev`、`_lx/_ly/_lz`)
- ⚠️ **限制**:forge2d 是 2D 物理,無法真 3 軸翻滾 → 目前「滾」是 2D 滑動+自轉配 3D 渲染。要 YoiLog 那種真滾需上 3D 物理引擎(下一步選項)。

**Iteration 7(完成,analyze 0 issues)— oimo 真 3D 物理**
- 使用者選「先自寫真 3D 物理(oimo)」。改用 [`oimo_physics`](https://pub.dev/packages/oimo_physics)(純 Dart 3D 剛體引擎)取代 home 的 forge2d:
  - 菸盒=3D Box 剛體(**真翻滾**,四元數)、香菸=3D Cylinder(**真滾動**)
  - 地面托盤(floor + 4 牆)、傾斜→平面重力、fixed 1/60 step(處理 120Hz ProMotion)
  - 軟體 pinhole 相機投影 + 逐面/逐段四元數打光、接觸陰影、pop-in、撞擊近似(速度驟降→粒子+haptic)、拖曳 grab(unproject 到地面)
  - **效能**:只有最近 `_maxLiveRecords`(26 筆=52 剛體)當活躍剛體 + oimo 自動睡眠;常數都在檔頂可調(`_trayW/_camH/_camZ/_gDown/_tiltMul/_maxLiveRecords`)
- 加依賴 `oimo_physics`、`vector_math`。forge2d 暫留 pubspec(未用)。

## ⏸️ 等使用者實機回饋(需 STOP + 重跑 flutter run,因為加了原生依賴)

⚠️ **相機角度/縮放/傾斜方向都是我盲調的預設值**,需要使用者實機看一輪校正(太近/太遠?角度?傾斜方向反了?滾動力道?)。
已完成且 analyze 乾淨:A(止血)、B(juice)、C3(圖鑑)、D1(nav)、D2(stats)、**oimo 真 3D 物理**。

⚠️ **尚未在模擬器實跑驗證視覺**(headless 無法截圖)——請 hot-reload 看實際效果再給方向。碰撞衝量門檻、粒子量、`_cuteify` 飽和度都還需依實機微調。

---

## 0. 殘酷的一句話總結

> **YoiLog 的全部魅力 = 圓潤可愛、會「滾」的 3D 物件不斷累積。你現在的菸盒是 Box2D 的方形多邊形(`setAsBoxXY`)+ `angularDamping: 2.5` —— 它在物理上不可能滾,只會翻倒、卡住、瞬間躺平。你把參考作品「不是」的那個東西做出來了。**

其餘所有問題(視覺、IA、stats、留存)都是次要的;在「物件本身令人想把玩」這件事做到之前,修圖表或資料庫都沒意義。

---

## 1. YoiLog 是什麼(已查證)

| 項目 | 事實 |
|------|------|
| 開發者 / 平台 | 個人開發者 清水大樹;**僅 iOS / iPadOS / visionOS**,無 Android |
| 評價 | JP App Store **4.7 星 / ~5,488 則**,發表推文 ~19.4 萬讚,多家媒體報導 |
| 核心迴圈 | 掃條碼 → 自動帶出品牌+容量 → 確認 → 存檔 → **可愛 3D 空罐「啪」地掉進畫面** |
| 招牌互動 | 累積的罐子隨手機傾斜「**コロコロ**」滾來滾去(圓潤幾何 → 真的會滾) |
| 資料庫 | ~8,000 種酒,使用者掃描眾包擴充 |
| 資訊架構 | 底部 **3 分頁**:Home(滾動堆疊)/ Browse(人氣排行+想喝清單)/ Records(圖表+月曆+HealthKit) |
| 商業模式 | 免費(玩具+基本記錄,有廣告);**YoiLog+** ¥220/月 or ¥2,200/年解鎖圖表+月曆 |
| 視覺 DNA | **chibi 變形、圓潤、軟邊、玩具感**,非寫實;每款顏色不同;預設「可愛扁平」,金屬寫實質感是付費升級 |
| 情感定位 | 把「負(抽菸/喝酒)變成資產(收藏)」,**靠可見度溫柔提醒,不說教**(BuzzFeed 標題:「可愛到要小心別喝太多」) |

**最大設計啟示**:玩具就是產品,記錄只是藉口。先把「圓潤、會滾、掉落有手感、不斷累積」做到位,圖表是次要、是拿來收費的。

---

## 2. 逐維度差距評分

| 維度 | 差距 | 一句話 |
|------|------|--------|
| **物理手感 / juice** | 🔴 鴻溝 | 方形多邊形+高 angularDamping → 不會滾;無掉落 squash、無音效、無觸覺、無粒子;假陰影膠在物件下 |
| **視覺 / 物件質感** | 🔴 鴻溝 | 假 3D(正交剪切,無透視)、單色平塗、無漸層/高光、硬邊方塊、刺眼原色;**更好的渲染器 `scene_2d_view.dart` 死在 tree 裡沒用** |
| **收集 / 留存迴圈** | 🔴 鴻溝 | 老化系統(你獨有的好點子)壞掉:只在 spawn 算一次、永不動畫;pile **每週 reset 不累積** → 明天沒有理由打開 |
| **資訊架構 / 導航** | 🔴 鴻溝 | 無 tab bar;六個無標籤圓圈浮在物理場景上、會被掉落菸盒蓋住;scanner 是假的;group 是進不去的死碼 |
| **首次體驗 / 空狀態** | 🔴 鴻溝 | 空白 cream void + 六個圓圈;**UI 對比綁在 `smoke=records/15`,空的時候最淡** → 第一次打開反而最看不見按鈕;無 onboarding |
| **數據視覺化 / stats** | 🟠 重大 | 只有 all-time;明明有 `filteredRecordsProvider` 卻沒接;trend 是假的(只放了個 icon);period-aware 的 `stats_header.dart` 寫了卻是死碼 |
| **記錄流程** | 🟠 重大 | 2 tap 夠快(全 app 最好的決定),但**完全沒有回饋**:無觸覺、無音效、無動畫確認;掃描器是假的;無「事後補記/最近常用」 |

---

## 3. 跨維度的重複病灶(改一處、多維度受益)

1. **菸盒不會滾** — `physics_scene.dart:140`(`angularDamping: 2.5`)、`:143`(`setAsBoxXY`)。同時拖垮 手感/視覺/收集 三個維度。
2. **老化只在 spawn 算一次** — `physics_scene.dart:122`(用 `recs.length` 當 diff key)、`:131`(高度只設一次)。差異化好點子卻沒 live 動畫。
3. **pile 每週 reset** — home 綁 `filteredRecordsProvider`(預設 week)→ 收藏不累積,殺掉整個「填滿畫面」的多巴胺迴圈。
4. **一堆更好的死碼**:`scene_2d_view.dart`(有真透視+旋轉陰影,比現役好)、`stats_header.dart`(period-aware)、`group_placeholder_screen.dart`(進不去)。
5. **效能反模式**:每 frame `setState({})` 重建整棵樹 + `shouldRepaint` 永遠 `true` + 每 frame 每面 new List/Path/Paint → 物件睡著了也在 60fps 重算。手感再好也會卡。
6. **⚠️ 資料毀損風險**:`record_storage.dart:30-32` 任何 JSON parse 失敗 → `catch (_) { _records = []; }` → **靜默清空使用者全部記錄**;整檔覆寫、無 atomic write、無 schema version。
7. **drift 是謊言**:`pubspec.yaml` 拉了 drift/sqlite3/riverpod_generator,plan.md 也說用 drift —— 但 `lib/` 裡 0 引用,儲存其實是手寫 JSON 檔。
8. **主題自相矛盾**:`theme.dart` 是深色琥珀(成熟/grungy),但 home 被硬改成 cream 淺色,還隨抽菸量變暗,所有 modal 又是深色 → 沒有單一方向。**與 YoiLog 的淺色可愛路線直接衝突(需決策)**。

---

## 4. 優先級 Backlog(依你要的 3 → 2 → 1,並標注依賴)

> 你的順序:3 盤點(✅ 本文)→ 2 視覺質感 → 1 會滾手感。
> **關鍵發現:2 和 1 是同一個根** —— 把菸盒「圓潤化」同時修好「看起來廉價」和「不會滾」。所以它們應該一起做。

### 🩹 Phase A — 先止血(便宜、擋住一切,建議先做)
- **A1 資料層不要再清空全部記錄**:移除 catch-all 清空、加 schema version、atomic write(temp + rename)。`record_storage.dart:30-47`。`S`
- **A2 painter 改用 Listenable repaint**,`shouldRepaint` 比對 frame、重用 buffer,停止每 frame 重建整樹。`physics_scene.dart:168,551,411-414`。`M`

### 🎨 Phase B — 把「菸盒」做成主角(你的 2 + 1 合併,最高槓桿)
- **B1【視覺2+手感1】圓潤化 + 真 3D**:菸盒改圓角/倒角輪廓 + chibi 比例;把死掉的 `scene_2d_view.dart` 的真透視除法 + 旋轉感知陰影扶正為現役,刪掉 `physics_scene.dart:422-433` 的正交剪切假 3D。一次修好 深度/假陰影/廉價方塊感。`L`
- **B2【手感1】讓它真的會滾**:碰撞幾何改圓角/膠囊,`angularDamping` 2.5 → ~0.2,調 restitution/friction → 傾斜時慢慢 tumble-roll(コロコロ)。`physics_scene.dart:140-145`。`M`
- **B3【視覺2】材質**:每面垂直漸層 + 軟高光帶(箔/玻璃紙感,取代死板平塗)+ 堆疊接觸陰影。`physics_scene.dart:450-494`。`M`
- **B4【手感1】掉落 juice**:真高度掉入 + scale-pop + 落地 squash-and-stretch + 塵土粒子 + 落地 `HapticFeedback` + 軟音效(節流)。`physics_scene.dart:134-145`。`M`
- **B5【視覺2】配色 + 老化**:菸盒色改柔和略降飽和(別 lerp 到純黑當陰影);把「掃描線式」老化換成真壓扁(輪廓抖動 + AO + 玻璃紙撕裂),且 live 動畫。`brand_data.json` + `physics_scene.dart:451,462,529-538`。`M~L`

### ♻️ Phase C — 讓它有理由明天再打開(留存,chasm 級,雖不在你列的清單但很關鍵)
- **C1 pile 持久累積**,不再每週 reset(舊的老化成菸蒂/灰沉到後層)。`physics_scene.dart:217` 解綁 filtered。`M`
- **C2 老化 live**:每 frame/每分鐘從 `agentProgress` 重算,移除 length-diff。`physics_scene.dart:122`。`M`
- **C3 圖鑑變 dex**:用真 3D 菸盒圖、首次解鎖揭示動畫 + 觸覺、稀有度,「你的收藏/品味」框架取代懲罰式清單。`collection_screen.dart`。`L`

### 🧭 Phase D — 讓人找得到功能(IA / stats,可與 C 並行)
- **D1 底部 NavigationBar**(Home/Stats/Collection/Settings)取代浮動圓圈;物理場景 full-bleed 在後。`home_screen.dart` + 刪 `physics_scene.dart:257-265`。`M`
- **D2 stats 接 `filteredRecordsProvider`** + 加真 trend LineChart(日/週/月) + 修花費計算。`stats_screen.dart:12,16-27`。`S~M`
- **D3 處理死碼/假功能**:scanner 要嘛重啟 mobile_scanner、要嘛誠實標成「手動輸入」;group 接上或刪除。`L`

---

## 5. 兩個需要你決策的產品分岔

1. **美術方向**:YoiLog 是**淺色 / 柔和 / 圓潤 / 可愛**;你的 plan.md 選的是**深色琥珀 / 成熟 / grungy**。兩者不能並存。要走 YoiLog 可愛路線、堅持深色成熟路線、還是混搭?**這決定 Phase B 怎麼做。**
2. **倫理方向**:目前唯一的迴圈是「抽越多、堆越多」,這正是 YoiLog 評論點出的悖論,對菸品 App 還有上架風險。要慶祝消費(高黏著、高風險),還是讓老化/腐爛把人推向「少抽」(可辯護,但獎勵視覺要重設計)?
