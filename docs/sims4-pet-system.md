# The Sims 4《貓狗成群》寵物系統 → 毛孩之家 對照表

> 研究日期：2026-10-18。資料來自搜尋引擎摘要（Carl's Sims 4 Guide、Sims Wiki、Game Rant、Sims Community 等），沒有逐頁讀過原文。標 ⚠ 的是來源之間說法不一致，或只有單一來源，之後有 Sims 4 可以實測時再確認。

## 一、Sims 4 的寵物系統怎麼運作

| 面向 | Sims 4 的做法 | 來源狀況 |
|---|---|---|
| 取得方式 | 用手機到收容所領養（付費，可看最多 3 隻動物與個性）；也可以自己用 Create-a-Pet 做 | 多個來源一致 |
| 個性 | 每隻最多 3 個特質，影響自主行為；特質要靠「認識牠（Get to Know）」互動才會慢慢揭露。部分特質互斥（例如黏人 vs 高冷） | 一致 |
| 貓的特質（17 個） | Affectionate, Aloof, Clever, Curious, Fluffy, Free Spirit, Friendly, Frisky, Glutton, Lazy, Mischievous, Playful, Prowler, Skittish, Spoiled, Talkative, Territorial | 一致 |
| 需求 | 飢餓、膀胱、精力、玩樂 | 一致 |
| 人生階段 | 幼年、成年、老年；壽命比人短；**只會老死**；家庭關閉老化時寵物也不會老 | 一致（具體天數各來源不同 ⚠） |
| 被忽略 | 忽略太久，動物管制人員會把寵物帶走 | ⚠ 單一來源 |
| 離家出走 | 沒絕育的寵物會跑出去，回來時可能懷孕（1–3 隻） | 一致 |
| 訓練 | 「寵物訓練」技能 5 級；**狗**可以學指令（坐下、握手、裝死、接飛盤…），**貓學不會把戲**，貓只能玩障礙賽 | 一致 |
| 行為塑造 | 稱讚／責罵影響寵物的行為習慣（例如爬家具 vs 用寵物床）；固執或被寵壞的寵物效果差 | 一致 |
| 獸醫 | 獸醫技能可以做年齡增減點心；有寵物醫院 | 一致 |
| 死亡 | 只有老死；有「長生不老藥」類道具可復活 | 一致 |

## 二、本模組的實作對照

| Sims 4 | 毛孩之家 v0.1 | 狀態 | 說明 |
|---|---|---|---|
| 收容所領養 | `adoption.lua`：每天輪替 3 隻，個性全部可見，要付費 | ✅ 已做、已測試 | 名字不會重複；金額不足或家庭已滿會拒絕；生成失敗不扣錢 |
| 在街上收養（Sims 4 的「流浪動物」） | 領養流浪貓：個性隱藏，靠「認識牠」揭露 | ✅ 已做 | 能不能真的把街貓帶回家取決於第 0 階段探勘 |
| 最多 3 個特質、互斥 | 13 個貓特質，1–3 個，互斥雙向檢查 | ✅ | 數值在 `data/traits.lua`，社群可以直接改 |
| 認識牠揭露特質 | `get_to_know`：機率取決於親密度、聰明（快）和高冷（慢） | ✅ | 全部揭露後不消耗冷卻 |
| 四種需求 | 飢餓、精力、玩樂、貓砂 | ✅ | 睡眠時段精力回復；貓砂盆全家共用 |
| 三階段、只會老死 | 幼貓 5 天／成貓 16 天／老貓 8 天（可調壽命倍率、可關閉老化） | ✅ | 每隻 ±15% 壽命隨機；死亡時親近的 Zoi 會哀傷 |
| 忽略 → 被帶走 | 連續忽略後先警告，再**離家出走**，之後可能回家，7 天沒回來變回流浪貓 | ✅ 改良 | 比「被帶走」溫和；可在設定關閉 |
| 寵物訓練技能 5 級 | Zoi 的 `Pet Training` 5 級，影響塑造速度；聰明的貓給更多經驗 | ✅ | |
| 稱讚／責罵 | 責罵只在「剛做壞事 90 分鐘內」有效；被寵壞、調皮的貓效果差 | ✅ | 三種壞習慣：抓家具、打翻東西、跳流理台 |
| 玩樂、餵食、擁抱、梳毛、清貓砂 | 全部有，各有冷卻 | ✅ | 冷卻防止洗點數 |
| 心情 | 由需求推算：開心、愛玩、精力充沛、滿足、睡覺、難過、不舒服、緊張、生氣 | ✅ | 心情會給親近的 Zoi 加成或擔心狀態（需要遊戲支援 buff） |
| 親密度 | 每個 Zoi 與每隻寵物各一個 0–100 值，分四級 | ✅ | 幼貓更容易親近 |
| 狗與狗的指令 | — | ❌ 未做 | 目前遊戲只有貓有完整動畫與互動，等探勘結果 |
| 貓的障礙賽 | — | ❌ 未做 | |
| 懷孕與繁殖 | — | ❌ 未做 | 規劃在 v0.3 之後 |
| 獸醫技能、年齡點心、寵物醫院 | — | ❌ 未做 | 規劃在 v0.3 之後 |
| 寵物服裝／造型、Create-a-Pet | — | ❌ 未做 | 外觀由遊戲決定，需要 ModKit 資產 |

## 三、刻意和 Sims 4 不同的地方

1. **離家而不是被帶走**：更符合 inZOI 的「生活感」，也更容易道歉（回家的可能性）。
2. **貓砂盆全家共用一個動作**：減少重複點擊。
3. **所有平衡數值都在資料表**：不用改程式就能調整難度。
4. **Zoi 的訓練技能是全域的**（跟人走，不跟寵物走）：和 Sims 4 一致。

## 四、平衡檢查（`tests/test_pets.lua` 的模擬 + 手動探索）

| 玩家行為 | 20 天內結果 |
|---|---|
| 完全不管 | 約 2–3.5 天後離家出走 |
| 每天只照顧 1 次（傍晚） | 不會離家；約 57% 的時間狀態良好 |
| 每天照顧 2 次（早晚） | 不會離家；約 94% 的時間狀態良好 |
| 每天 4 次 | 不會離家；約 91%（和 2 次差不多，多的只是在做白工） |

⚠ inZOI 一個遊戲日對應多少現實時間還不知道（第 0 階段 P7 會量），到時候要用真實時間重新校準「2–3 天會離家」這個數字是否太嚴。

## 來源

- [Carl's Sims 4 Guide：Cats & Dogs 領養、訓練與照顧](https://www.carls-sims-4-guide.com/expansionpacks/pets/cats-dogs.php)
- [Sims Wiki：The Sims 4: Cats & Dogs](https://sims.fandom.com/wiki/The_Sims_4:_Cats_%26_Dogs)、[Life stages (pet)](https://sims.fandom.com/wiki/Life_stages_(pet))、[Pet training](https://sims.fandom.com/wiki/Pet_training)
- [Game Rant：Cats & Dogs Complete Guide](https://gamerant.com/the-sims-4-cats-dogs-complete-guide/)、[訓練寵物](https://gamerant.com/the-sims-4-cats-dogs-train-pets-guide/)
- [Sims Community：貓與狗特質](https://simscommunity.info/2017/10/09/the-sims-4-cats-dogs-cat-and-dog-traits/)、[寵物訓練技能](https://simscommunity.info/2017/11/12/the-sims-4-cats-dogs-pet-training-skill-guide/)
- [EA Help：Pet training skill](https://help.ea.com/hu/articles/the-sims/the-sims-4/pet-training-skill)
