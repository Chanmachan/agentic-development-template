#!/usr/bin/env python3
"""Workflow 出力 JSON → 監査カテゴリ markdown レンダラ。

usage: render_audit.py <workflow-output.json> <cat_num> <cat_title> <out.md>
finding 形式 (progress.md 記載のルール):
  id: AUD-<cat>-<連番>, severity, verified, file:line, 1行要約, 根拠, 修正方針, 工数感, 依存関係
"""
import json
import sys
from datetime import datetime, timezone, timedelta

SEV_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "suggestion": 4}

def main():
    src, cat_num, cat_title, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    data = json.load(open(src))
    res = data["result"]
    findings = res.get("findings") or []
    failed = res.get("failedScanners") or []

    active = [f for f in findings if not f.get("refuted")]
    refuted = [f for f in findings if f.get("refuted")]
    active.sort(key=lambda f: (SEV_ORDER.get(f.get("severity"), 9)))

    jst = timezone(timedelta(hours=9))
    now = datetime.now(jst).strftime("%Y-%m-%dT%H:%M:%S%z")

    counts = {}
    for f in active:
        counts[f.get("severity", "?")] = counts.get(f.get("severity", "?"), 0) + 1
    count_str = " / ".join(f"{k}:{v}" for k, v in sorted(counts.items(), key=lambda kv: SEV_ORDER.get(kv[0], 9)))

    lines = []
    lines.append(f"# {cat_num} {cat_title} — 監査結果")
    lines.append("")
    lines.append(f"- 生成: {now} (ultracode audit)")
    lines.append(f"- findings: {len(active)} 件 ({count_str or 'なし'})、反証チェックで棄却: {len(refuted)} 件")
    lines.append(f"- 走査エージェント欠落: {', '.join(failed) if failed else 'なし (全走査完了)'}")
    lines.append("- verified=true は critical/high に対する sonnet 反証チェック通過を意味する。medium 以下は設計上 verified=false のまま。")
    lines.append("")

    for i, f in enumerate(active, 1):
        fid = f"AUD-{cat_num.lstrip('0') or cat_num}-{i:02d}"
        lines.append(f"## {fid}: {f.get('summary', '').strip()}")
        lines.append("")
        lines.append(f"- severity: {f.get('severity')}")
        lines.append(f"- verified: {str(bool(f.get('verified'))).lower()}")
        lines.append(f"- file: {f.get('file', '').strip()}")
        if f.get("scanner"):
            lines.append(f"- 検出: {f['scanner']}")
        lines.append(f"- 工数感: {f.get('effort', '?')}")
        dep = (f.get("depends") or "").strip()
        lines.append(f"- 依存: {dep if dep else 'なし'}")
        lines.append("")
        lines.append(f"**根拠**: {f.get('evidence', '').strip()}")
        lines.append("")
        lines.append(f"**修正方針の素案**: {f.get('fix', '').strip()}")
        vn = (f.get("verify_note") or "").strip()
        if vn:
            lines.append("")
            lines.append(f"**反証チェック所見**: {vn}")
        lines.append("")

    if refuted:
        lines.append("## 反証チェックで棄却された finding (参考)")
        lines.append("")
        for f in refuted:
            lines.append(f"- ~~{f.get('summary', '').strip()}~~ ({f.get('file', '')}) — 棄却理由: {(f.get('verify_note') or '').strip()}")
        lines.append("")

    with open(out, "w") as fh:
        fh.write("\n".join(lines))
    print(f"wrote {out}: {len(active)} active, {len(refuted)} refuted")

if __name__ == "__main__":
    main()
