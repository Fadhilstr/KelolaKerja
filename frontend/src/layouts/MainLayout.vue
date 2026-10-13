<template>
  <q-layout view="lHh Lpr lFf">
    <q-header elevated class="bg-primary text-white">
      <q-toolbar>
        <q-btn flat dense round icon="menu" aria-label="Menu" @click="leftDrawerOpen = !leftDrawerOpen" />
        <q-toolbar-title class="text-weight-bold">
          KelolaKerja
        </q-toolbar-title>
        <div class="row items-center q-gutter-sm">
          <q-chip color="primary-light" text-color="white" icon="account_circle">
            {{ user.name }} ({{ user.role }})
          </q-chip>
          <q-btn flat round dense icon="logout" @click="logout" title="Keluar">
            <q-tooltip>Keluar Aplikasi</q-tooltip>
          </q-btn>
        </div>
      </q-toolbar>
    </q-header>

    <q-drawer v-model="leftDrawerOpen" show-if-above bordered content-class="bg-grey-1">
      <q-list>
        <q-item-label header class="text-grey-8 text-weight-bold">
          MENU UTAMA
        </q-item-label>

        <!-- Employee Menu -->
        <q-item clickable v-ripple to="/attendance" exact active-class="bg-blue-1 text-primary">
          <q-item-section avatar>
            <q-icon name="fingerprint" />
          </q-item-section>
          <q-item-section>
            <q-item-label>Absensi Wajah</q-item-label>
            <q-item-label caption>Check-In & Check-Out</q-item-label>
          </q-item-section>
        </q-item>

        <q-item clickable v-ripple to="/biometric-enrollment" exact active-class="bg-blue-1 text-primary">
          <q-item-section avatar>
            <q-icon name="face" />
          </q-item-section>
          <q-item-section>
            <q-item-label>Registrasi Wajah</q-item-label>
            <q-item-label caption>Pendaftaran Biometrik</q-item-label>
          </q-item-section>
        </q-item>

        <q-item clickable v-ripple to="/reports" exact active-class="bg-blue-1 text-primary">
          <q-item-section avatar>
            <q-icon name="assignment" />
          </q-item-section>
          <q-item-section>
            <q-item-label>Laporan Aktivitas</q-item-label>
            <q-item-label caption>Pelaporan Tugas Harian</q-item-label>
          </q-item-section>
        </q-item>

        <!-- Supervisor / Admin Menu -->
        <q-separator class="q-my-md" v-if="user.role === 'ADMIN' || user.role === 'SUPERVISOR'" />
        <q-item-label header class="text-grey-8 text-weight-bold" v-if="user.role === 'ADMIN' || user.role === 'SUPERVISOR'">
          SUPERVISI
        </q-item-label>

        <q-item clickable v-ripple to="/supervisor" exact active-class="bg-blue-1 text-primary" v-if="user.role === 'ADMIN' || user.role === 'SUPERVISOR'">
          <q-item-section avatar>
            <q-icon name="dashboard" />
          </q-item-section>
          <q-item-section>
            <q-item-label>Dashboard Tim</q-item-label>
            <q-item-label caption>Rekap Kehadiran Tim</q-item-label>
          </q-item-section>
        </q-item>

        <!-- Admin Only Menu -->
        <q-separator class="q-my-md" v-if="user.role === 'ADMIN'" />
        <q-item-label header class="text-grey-8 text-weight-bold" v-if="user.role === 'ADMIN'">
          ADMINISTRASI SISTEM
        </q-item-label>

        <q-item clickable v-ripple to="/admin" exact active-class="bg-blue-1 text-primary" v-if="user.role === 'ADMIN'">
          <q-item-section avatar>
            <q-icon name="analytics" />
          </q-item-section>
          <q-item-section>
            <q-item-label>Ringkasan Admin</q-item-label>
            <q-item-label caption>Statistik Keseluruhan</q-item-label>
          </q-item-section>
        </q-item>

        <q-item clickable v-ripple to="/admin/users" exact active-class="bg-blue-1 text-primary" v-if="user.role === 'ADMIN'">
          <q-item-section avatar>
            <q-icon name="people" />
          </q-item-section>
          <q-item-section>
            <q-item-label>Kelola Karyawan</q-item-label>
            <q-item-label caption>Manajemen Akun</q-item-label>
          </q-item-section>
        </q-item>

        <q-item clickable v-ripple to="/admin/audit" exact active-class="bg-blue-1 text-primary" v-if="user.role === 'ADMIN'">
          <q-item-section avatar>
            <q-icon name="security" />
          </q-item-section>
          <q-item-section>
            <q-item-label>Audit Log</q-item-label>
            <q-item-label caption>Jejak Aktivitas Sistem</q-item-label>
          </q-item-section>
        </q-item>
      </q-list>
    </q-drawer>

    <q-page-container>
      <router-view />
    </q-page-container>
  </q-layout>
</template>

<script>
export default {
  name: 'MainLayout',
  data () {
    return {
      leftDrawerOpen: false,
      user: JSON.parse(localStorage.getItem('kk_user') || '{}')
    }
  },
  methods: {
    async logout () {
      try {
        await this.$api.post('/auth/logout')
      } catch (e) {
        // Continue clearing storage even if request fails
      }
      localStorage.removeItem('kk_token')
      localStorage.removeItem('kk_user')
      this.$router.push('/login')
    }
  }
}
</script>

