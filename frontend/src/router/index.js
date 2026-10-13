import Vue from 'vue'
import VueRouter from 'vue-router'
import routes from './routes'

Vue.use(VueRouter)

export default function () {
  const Router = new VueRouter({
    scrollBehavior: () => ({ x: 0, y: 0 }),
    routes,
    mode: 'hash'
  })

  // RBAC Navigation Guard
  Router.beforeEach((to, from, next) => {
    const token = localStorage.getItem('kk_token')
    const userJson = localStorage.getItem('kk_user')
    const user = userJson ? JSON.parse(userJson) : null

    if (to.matched.some(record => record.meta.requiresAuth)) {
      if (!token || !user) {
        return next({ path: '/login', query: { redirect: to.fullPath } })
      }

      // Check Role Permissions
      if (to.meta.roles && !to.meta.roles.includes(user.role)) {
        return next({ path: '/unauthorized' })
      }
    } else if (to.path === '/login' && token && user) {
      // Already authenticated, redirect to appropriate role dashboard
      if (user.role === 'ADMIN') {
        return next('/admin')
      } else if (user.role === 'SUPERVISOR') {
        return next('/supervisor')
      } else {
        return next('/attendance')
      }
    }

    next()
  })

  return Router
}

