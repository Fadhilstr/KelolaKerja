const routes = [
  {
    path: '/login',
    component: () => import('pages/LoginPage.vue'),
    meta: { requiresAuth: false }
  },
  {
    path: '/',
    component: () => import('layouts/MainLayout.vue'),
    meta: { requiresAuth: true },
    children: [
      {
        path: '',
        redirect: to => {
          const u = JSON.parse(localStorage.getItem('kk_user') || '{}')
          if (u.role === 'ADMIN') return '/admin'
          if (u.role === 'SUPERVISOR') return '/supervisor'
          return '/attendance'
        }
      },
      // Employee Routes
      {
        path: 'attendance',
        component: () => import('pages/AttendancePage.vue'),
        meta: { requiresAuth: true, roles: ['EMPLOYEE', 'SUPERVISOR', 'ADMIN'] }
      },
      {
        path: 'biometric-enrollment',
        component: () => import('pages/BiometricEnrollmentPage.vue'),
        meta: { requiresAuth: true, roles: ['EMPLOYEE', 'SUPERVISOR', 'ADMIN'] }
      },
      {
        path: 'reports',
        component: () => import('pages/ReportsPage.vue'),
        meta: { requiresAuth: true, roles: ['EMPLOYEE', 'SUPERVISOR', 'ADMIN'] }
      },
      // Supervisor Routes
      {
        path: 'supervisor',
        component: () => import('pages/SupervisorDashboardPage.vue'),
        meta: { requiresAuth: true, roles: ['SUPERVISOR', 'ADMIN'] }
      },
      // Admin Routes
      {
        path: 'admin',
        component: () => import('pages/AdminDashboardPage.vue'),
        meta: { requiresAuth: true, roles: ['ADMIN'] }
      },
      {
        path: 'admin/users',
        component: () => import('pages/AdminUsersPage.vue'),
        meta: { requiresAuth: true, roles: ['ADMIN'] }
      },
      {
        path: 'admin/audit',
        component: () => import('pages/AdminAuditLogsPage.vue'),
        meta: { requiresAuth: true, roles: ['ADMIN'] }
      }
    ]
  },
  {
    path: '/unauthorized',
    component: () => import('pages/UnauthorizedPage.vue')
  },
  {
    path: '*',
    component: () => import('pages/Error404.vue')
  }
]

export default routes

