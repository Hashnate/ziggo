const BASE = '/admin-api'

async function req(path, opts = {}) {
  const res = await fetch(BASE + path, { credentials: 'same-origin', ...opts })
  if (res.status === 401) throw { status: 401, detail: 'Unauthorized' }
  if (!res.ok) {
    let d = {}
    try { d = await res.json() } catch (e) {}
    throw { status: res.status, detail: d.detail || 'Request failed' }
  }
  return res.json()
}

export const api = {
  me: () => req('/me'),
  dashboard: () => req('/dashboard'),
  referrals: () => req('/referrals'),
  login: (phone, password) => {
    const body = new URLSearchParams()
    body.append('phone_number', phone)
    body.append('password', password)
    return fetch(BASE + '/login', { method: 'POST', credentials: 'same-origin', body }).then(async (r) => {
      const d = await r.json().catch(() => ({}))
      if (!r.ok) throw { detail: d.detail || 'Login failed' }
      return d
    })
  },
  logout: () => fetch(BASE + '/logout', { method: 'POST', credentials: 'same-origin' }),
}
