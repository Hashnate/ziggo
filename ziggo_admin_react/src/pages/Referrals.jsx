import { useState, useEffect } from 'react'
import { api } from '../api'

export default function Referrals() {
  const [referrals, setReferrals] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    api.referrals()
      .then(setReferrals)
      .catch(e => console.error("Failed to fetch referrals:", e))
      .finally(() => setLoading(false))
  }, [])

  if (loading) {
    return <div className="p-8 text-center text-ziggo-muted font-bold animate-pulse">Loading Referrals...</div>
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-ziggo-ink">Referrals</h1>
          <p className="text-sm font-semibold text-ziggo-faint mt-1">Track driver and customer referral bonuses.</p>
        </div>
      </div>

      <div className="bg-white rounded-2xl border border-ziggo-line shadow-sm overflow-hidden">
        <table className="w-full text-left text-sm">
          <thead className="bg-ziggo-canvas/50 text-xs uppercase tracking-wider font-bold text-ziggo-faint border-b border-ziggo-line">
            <tr>
              <th className="px-6 py-4">Referrer</th>
              <th className="px-6 py-4">Referred User</th>
              <th className="px-6 py-4 text-right">Bonus Amount</th>
              <th className="px-6 py-4">Status</th>
              <th className="px-6 py-4">Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-ziggo-line">
            {referrals.map((ref) => (
              <tr key={ref.id} className="hover:bg-ziggo-canvas/50 transition">
                <td className="px-6 py-4">
                  <p className="font-bold text-ziggo-ink">{ref.referrer.name || 'Unknown'}</p>
                  <p className="text-xs text-ziggo-muted">{ref.referrer.phone || 'N/A'}</p>
                </td>
                <td className="px-6 py-4">
                  <p className="font-bold text-ziggo-ink">{ref.referred.name || 'Unknown'}</p>
                  <p className="text-xs text-ziggo-muted">{ref.referred.phone || 'N/A'}</p>
                </td>
                <td className="px-6 py-4 text-right font-black text-emerald-600">
                  Rs. {ref.amount.toFixed(2)}
                </td>
                <td className="px-6 py-4">
                  <span className={`inline-flex items-center px-2 py-1 rounded-md text-xs font-bold uppercase tracking-wider ${
                    ref.status === 'completed' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'
                  }`}>
                    {ref.status}
                  </span>
                </td>
                <td className="px-6 py-4 text-ziggo-muted font-medium text-xs">
                  {new Date(ref.created_at).toLocaleString()}
                </td>
              </tr>
            ))}
            {referrals.length === 0 && (
              <tr>
                <td colSpan="5" className="px-6 py-12 text-center text-ziggo-muted font-bold">
                  No referrals found
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
