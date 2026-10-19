# inZOI 寵物模組「毛孩之家 Paw Home」（暫定）

讓 inZOI 的 Zoi 能領養流浪貓或收容所的貓、在家照顧牠，玩法參考 The Sims 4《貓狗成群》。inZOI 目前還沒有寵物系統，這個模組用官方 ModKit 的 Lua 腳本和 Overlay UI 來補上。語系：繁體中文、English。

## 狀態

- 寵物引擎與介面已完成，**120 項自動測試**（Linux＋Windows CI）通過。
- 已有 **UE4SS adapter**（`mod/lua/pawhome/adapters/ue4ss.lua`）：2026-10-19 在 inZOI **v0.11.0** 通過 T1 冒煙測試（UE4SS 注入、mod 載入、存檔寫出），目前**安全模式**（所有能力關閉），也就是「虛擬寵物」：貓還不會出現在遊戲世界裡。
- **還沒驗證**：進存檔、生成貓、貓會不會自己走動（里程碑 M1，需要使用者同意並在場）。細節見 [`docs/ue4ss-adapter.md`](docs/ue4ss-adapter.md)、[`docs/compatibility.md`](docs/compatibility.md)。

## 現在就能玩玩看（不用開遊戲）

```bash
pip install lupa
python3 tools/preview_server.py
# 開啟 http://127.0.0.1:8765/?preview=1
```

用的是真正的 Lua 引擎，頁面最下面的「預覽工具」可以快轉遊戲時間，看需求下降、貓長大、被動保員帶走與付費領回。

## 跑測試

```bash
pip install lupa
python3 -I tests/run.py        # 120 passed, 0 failed
```

## 文件

| 文件 | 內容 |
|---|---|
| [docs/sims4-pet-system.md](docs/sims4-pet-system.md) | Sims 4 寵物系統研究與本模組的對照表（做了什麼、沒做什麼） |
| [docs/pet-mod-plan.md](docs/pet-mod-plan.md) | 玩法設計、專案結構與開發進程 |
| [docs/handoff-ue4ss-session.md](docs/handoff-ue4ss-session.md) | **交接給既有的 ZoiPets（UE4SS）本機 session**：兩個專案的關係、我查到的事實、風險與建議步驟 |
| [docs/handoff-local-session.md](docs/handoff-local-session.md) | **交接給本機 Claude Code session**（含第一則要貼的訊息） |
| [docs/setup-windows.md](docs/setup-windows.md) | Windows 開發環境安裝（搭配 `scripts/setup-windows.ps1`） |
| [docs/engineering-workflow.md](docs/engineering-workflow.md) | 開發分工與規則（角色、四眼原則、完成標準、遊戲操作同意層級、里程碑） |
| [docs/ue4ss-adapter.md](docs/ue4ss-adapter.md) | UE4SS adapter：操作方式、每個函式的驗證狀態、已知的實體貓資訊 |
| [docs/reviews/](docs/reviews/) | 審查紀錄 |
| [docs/phase0-probe.md](docs/phase0-probe.md) | 第 0 階段可行性探勘清單（接上遊戲前必做） |
| [docs/research-report.md](docs/research-report.md) | inZOI 模組製作方式與社群需求研究 |
