# 0003 開發分工與規則（現代開發流程）

- 日期：2026-10-18　狀態：**採用**　決定者：使用者授權雲端與本機兩個 session 自行決定（「高自主模式」）；兩個 session 經 2 輪討論一致同意。
- **背景**：使用者要求兩個 session 以現代開發分工進行開發，並自行訂定分工與規則。
- **決定**：採用 `docs/engineering-workflow.md` v1.0：PO／Dev／Review 三種角色與擁有權表；四眼原則；短命分支＋squash merge＋Conventional Commits；Definition of Done；審查嚴重度；測試金字塔（含全自動 T1 冒煙）；遊戲操作同意層級 T0–T3；ADR 記錄決定；SemVer＋CHANGELOG＋相容性表；工程要求（kill switch、啟動橫幅、未知 build 安全模式、存檔輪替、釘版本、回復計畫）；第一個里程碑 M1。
- **後果**：合併需非作者審查；遊戲內證據才算「已驗證」；啟動遊戲、發佈、改規格等仍須 PO 同意。尚未開啟 GitHub branch protection，目前靠約定。
- **未決**：PR／Issue 是否啟用（需 PO 同意）。
