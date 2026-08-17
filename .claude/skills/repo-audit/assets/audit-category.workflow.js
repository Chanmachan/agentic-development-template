export const meta = {
  name: 'audit-category',
  description: 'Scan one audit category with parallel sonnet scanners, adversarially verify critical/high findings',
  phases: [{ title: 'Scan' }, { title: 'Verify' }],
}

const FINDINGS = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'file', 'summary', 'evidence', 'fix', 'effort'],
        properties: {
          severity: { enum: ['critical', 'high', 'medium', 'low', 'suggestion'] },
          file: { type: 'string', description: 'path:line 形式。複数根拠はカンマ区切り' },
          summary: { type: 'string', description: '1行要約' },
          evidence: { type: 'string', description: '根拠(該当コードで実際に確認した内容)' },
          fix: { type: 'string', description: '修正方針の素案' },
          effort: { enum: ['S', 'M', 'L'] },
          depends: { type: 'string', description: '他指摘/前提への依存。無ければ空文字' },
        },
      },
    },
  },
}

const VERDICT = {
  type: 'object',
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean' },
    reason: { type: 'string' },
    adjusted_severity: { enum: ['critical', 'high', 'medium', 'low', 'suggestion', 'unchanged'] },
  },
}

const A = typeof args === 'string' ? JSON.parse(args) : args

phase('Scan')
const failed = []
const scans = await parallel(A.scanners.map(s => async () => {
  const opts = { label: s.label, phase: 'Scan', schema: FINDINGS, model: s.model || 'sonnet', effort: s.effort || 'medium' }
  let r = await agent(s.prompt, opts)
  if (!r) r = await agent(s.prompt, Object.assign({}, opts, { label: s.label + '-retry' }))
  if (!r) failed.push(s.label)
  return r
}))
const findings = scans.filter(Boolean).flatMap(r => (r.findings || []))
log(findings.length + ' findings collected from ' + (A.scanners.length - failed.length) + '/' + A.scanners.length + ' scanners; failed: ' + (failed.join(',') || 'none'))

phase('Verify')
const out = await parallel(findings.map((f, i) => async () => {
  if (f.severity !== 'critical' && f.severity !== 'high') return Object.assign({}, f, { verified: false })
  const p = 'あなたは監査 finding の反証チェッカー。このリポジトリを read-only で調べ、次の finding が本当に成立するかを、根拠ファイルを実際に開いて検証せよ。誤り・誇張・既に対策済み・引用行に根拠が無い、のいずれかなら refuted=true とし reason に理由を書く。成立するなら refuted=false。severity が過大/過小なら adjusted_severity で訂正(妥当なら unchanged)。finding: ' + JSON.stringify(f)
  const vopts = { label: 'verify-' + i, phase: 'Verify', schema: VERDICT, model: 'sonnet', effort: 'medium' }
  let v = await agent(p, vopts)
  if (!v) v = await agent(p, Object.assign({}, vopts, { label: 'verify-' + i + '-retry' }))
  if (!v) return Object.assign({}, f, { verified: false, verify_note: 'verifier unavailable (null after retry)' })
  if (v.refuted) return Object.assign({}, f, { verified: false, refuted: true, verify_note: v.reason })
  const sev = (v.adjusted_severity && v.adjusted_severity !== 'unchanged') ? v.adjusted_severity : f.severity
  return Object.assign({}, f, { severity: sev, verified: true, verify_note: v.reason })
}))
return { cat: A.cat, findings: out, failedScanners: failed }
