import axios from 'axios'

const api = axios.create({
  baseURL: '/api',
  timeout: 15000,
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  }
})

// Request interceptor: attach Bearer token
api.interceptors.request.use(
  config => {
    const token = localStorage.getItem('kk_token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    return config
  },
  error => Promise.reject(error)
)

// Response interceptor: handle 401 unauthenticated
api.interceptors.response.use(
  response => response,
  error => {
    if (error.response && error.response.status === 401) {
      localStorage.removeItem('kk_token')
      localStorage.removeItem('kk_user')
      if (window.location.hash !== '#/login') {
        window.location.hash = '#/login'
      }
    }
    return Promise.reject(error)
  }
)

export default ({ Vue }) => {
  Vue.prototype.$axios = axios
  Vue.prototype.$api = api
}

export { api }

