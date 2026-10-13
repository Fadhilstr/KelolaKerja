<template>
  <q-page class="q-pa-md">
    <div class="row justify-between items-center q-mb-md">
      <div>
        <div class="text-h6 text-weight-bold">Manajemen Karyawan & Akun</div>
        <div class="text-caption text-grey-7">Kelola akses, jabatan, dan status keaktifan seluruh pengguna sistem.</div>
      </div>
      <q-btn color="primary" icon="person_add" label="Tambah Karyawan" @click="openDialog" />
    </div>

    <q-card class="shadow-1">
      <q-table
        :data="users"
        :columns="columns"
        row-key="id"
        :loading="loading"
      >
        <template v-slot:body-cell-is_active="props">
          <q-td :props="props">
            <q-toggle
              v-model="props.row.is_active"
              :true-value="1"
              :false-value="0"
              color="positive"
              @input="toggleStatus(props.row)"
            />
          </q-td>
        </template>
        <template v-slot:body-cell-face_registered="props">
          <q-td :props="props">
            <q-badge :color="props.value ? 'positive' : 'grey-6'">
              {{ props.value ? 'Terdaftar' : 'Belum' }}
            </q-badge>
          </q-td>
        </template>
      </q-table>
    </q-card>

    <!-- Create User Dialog -->
    <q-dialog v-model="dialogOpen">
      <q-card style="min-width: 400px; max-width: 550px;">
        <q-card-section>
          <div class="text-h6">Pendaftaran Karyawan Baru</div>
        </q-card-section>

        <q-card-section class="q-pt-none q-gutter-sm">
          <q-input v-model="form.employee_code" label="NIK / Kode Karyawan" outlined dense />
          <q-input v-model="form.name" label="Nama Lengkap" outlined dense />
          <q-input v-model="form.username" label="Username Login" outlined dense />
          <q-input v-model="form.email" label="Email" outlined dense />
          <q-input v-model="form.password" label="Password Sementara" type="password" outlined dense />
          <q-select
            v-model="form.role"
            :options="['EMPLOYEE', 'SUPERVISOR', 'ADMIN']"
            label="Role Akses"
            outlined
            dense
          />
          <q-input v-model="form.department" label="Departemen / Divisi" outlined dense />
          <q-input v-model="form.position" label="Posisi / Jabatan" outlined dense />
        </q-card-section>

        <q-card-actions align="right">
          <q-btn flat label="Batal" color="grey" v-close-popup />
          <q-btn label="Simpan Akun" color="primary" @click="saveUser" :loading="saving" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script>
export default {
  name: 'AdminUsersPage',
  data () {
    return {
      users: [],
      loading: false,
      dialogOpen: false,
      saving: false,
      form: {
        employee_code: '',
        name: '',
        username: '',
        email: '',
        password: '',
        role: 'EMPLOYEE',
        department: '',
        position: ''
      },
      columns: [
        { name: 'employee_code', label: 'NIK', field: 'employee_code', align: 'left' },
        { name: 'name', label: 'Nama', field: 'name', align: 'left' },
        { name: 'username', label: 'Username', field: 'username', align: 'left' },
        { name: 'role', label: 'Role', field: 'role', align: 'center' },
        { name: 'department', label: 'Departemen', field: 'department', align: 'left' },
        { name: 'face_registered', label: 'Biometrik', field: 'face_registered', align: 'center' },
        { name: 'is_active', label: 'Aktif', field: 'is_active', align: 'center' }
      ]
    }
  },
  mounted () {
    this.fetchUsers()
  },
  methods: {
    async fetchUsers () {
      this.loading = true
      try {
        const res = await this.$api.get('/admin/users')
        this.users = res.data.data || []
      } catch (e) {
        // Handle error
      } finally {
        this.loading = false
      }
    },
    openDialog () {
      this.form = {
        employee_code: '',
        name: '',
        username: '',
        email: '',
        password: '',
        role: 'EMPLOYEE',
        department: '',
        position: ''
      }
      this.dialogOpen = true
    },
    async saveUser () {
      this.saving = true
      try {
        const res = await this.$api.post('/admin/users', this.form)
        if (res.data.success) {
          this.$q.notify({ type: 'positive', message: 'Akun karyawan baru berhasil dibuat' })
          this.dialogOpen = false
          await this.fetchUsers()
        }
      } catch (e) {
        this.$q.notify({ type: 'negative', message: 'Gagal membuat user baru' })
      } finally {
        this.saving = false
      }
    },
    async toggleStatus (user) {
      try {
        await this.$api.put(`/admin/users/${user.id}/status`, { is_active: user.is_active })
        this.$q.notify({ type: 'positive', message: `Status akun ${user.username} diperbarui` })
      } catch (e) {
        this.$q.notify({ type: 'negative', message: 'Gagal mengubah status akun' })
        await this.fetchUsers()
      }
    }
  }
}
</script>

