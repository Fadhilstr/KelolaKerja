<template>
  <q-layout view="hHh lpR fFf">
    <q-page-container>
      <q-page class="window-height window-width row justify-center items-center bg-grey-2">
        <div class="col-xs-11 col-sm-6 col-md-4">
          <q-card class="q-pa-md shadow-2">
            <q-card-section class="text-center">
              <q-icon name="fingerprint" size="56px" color="primary" />
              <div class="text-h5 text-weight-bold q-mt-sm">KelolaKerja</div>
              <div class="text-subtitle2 text-grey-7">Sistem Absensi & Pelaporan Karyawan</div>
            </q-card-section>

            <q-card-section>
              <q-banner v-if="errorMessage" rounded class="bg-red-1 text-negative q-mb-md">
                {{ errorMessage }}
              </q-banner>

              <q-form @submit.prevent="handleLogin" class="q-gutter-md">
                <q-input
                  v-model="username"
                  label="Username atau Email"
                  outlined
                  dense
                  :disable="loading"
                  autofocus
                  :rules="[val => !!val || 'Username wajib diisi']"
                >
                  <template v-slot:prepend>
                    <q-icon name="person" />
                  </template>
                </q-input>

                <q-input
                  v-model="password"
                  label="Password"
                  type="password"
                  outlined
                  dense
                  :disable="loading"
                  :rules="[val => !!val || 'Password wajib diisi']"
                >
                  <template v-slot:prepend>
                    <q-icon name="lock" />
                  </template>
                </q-input>

                <div>
                  <q-btn
                    type="submit"
                    label="Masuk ke Akun"
                    color="primary"
                    class="full-width q-py-sm"
                    :loading="loading"
                  />
                </div>
              </q-form>
            </q-card-section>

            <q-card-section class="text-center text-caption text-grey-6">
              Dilindungi oleh Role-Based Access Control dan Verifikasi Biometrik
            </q-card-section>
          </q-card>
        </div>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script>
export default {
  name: 'LoginPage',
  data () {
    return {
      username: '',
      password: '',
      loading: false,
      errorMessage: ''
    }
  },
  methods: {
    async handleLogin () {
      this.loading = true
      this.errorMessage = ''
      try {
        const response = await this.$api.post('/auth/login', {
          username: this.username,
          password: this.password
        })

        if (response.data.success) {
          const { token, user } = response.data.data
          localStorage.setItem('kk_token', token)
          localStorage.setItem('kk_user', JSON.stringify(user))

          // Redirect based on role
          if (user.role === 'ADMIN') {
            this.$router.push('/admin')
          } else if (user.role === 'SUPERVISOR') {
            this.$router.push('/supervisor')
          } else {
            this.$router.push('/attendance')
          }
        }
      } catch (err) {
        if (err.response && err.response.data && err.response.data.message) {
          this.errorMessage = err.response.data.message
        } else {
          this.errorMessage = 'Gagal terhubung ke server. Periksa koneksi jaringan Anda.'
        }
      } finally {
        this.loading = false
      }
    }
  }
}
</script>

