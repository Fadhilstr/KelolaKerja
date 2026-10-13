<template>
  <q-page class="q-pa-md">
    <div class="text-h6 text-weight-bold q-mb-md">Dashboard Administrator</div>

    <div class="row q-col-gutter-md q-mb-md" v-if="summary">
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-indigo-1 text-indigo-9 shadow-1">
          <q-card-section>
            <div class="text-caption">Total Karyawan Aktif</div>
            <div class="text-h5 text-weight-bolder">{{ summary.total_employees || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-teal-1 text-teal-9 shadow-1">
          <q-card-section>
            <div class="text-caption">Absen Hadir Hari Ini</div>
            <div class="text-h5 text-weight-bolder">{{ summary.present_count || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-amber-1 text-amber-9 shadow-1">
          <q-card-section>
            <div class="text-caption">Keterlambatan Masuk</div>
            <div class="text-h5 text-weight-bolder">{{ summary.late_count || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-deep-orange-1 text-deep-orange-9 shadow-1">
          <q-card-section>
            <div class="text-caption">Belum Melakukan Absen</div>
            <div class="text-h5 text-weight-bolder">{{ summary.not_present_count || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
    </div>

    <!-- Attendance Live Feed Table -->
    <q-card class="shadow-1">
      <q-card-section>
        <div class="text-subtitle1 text-weight-bold">Daftar Kehadiran Seluruh Karyawan (Hari Ini)</div>
      </q-card-section>
      <q-table
        :data="records"
        :columns="columns"
        row-key="id"
        :loading="loading"
        no-data-label="Belum ada data kehadiran hari ini."
      >
        <template v-slot:body-cell-status="props">
          <q-td :props="props">
            <q-badge :color="props.value === 'PRESENT' ? 'positive' : (props.value === 'LATE' ? 'warning' : 'negative')">
              {{ props.value }}
            </q-badge>
          </q-td>
        </template>
      </q-table>
    </q-card>
  </q-page>
</template>

<script>
export default {
  name: 'AdminDashboardPage',
  data () {
    return {
      summary: null,
      records: [],
      loading: false,
      columns: [
        { name: 'employee_code', label: 'NIK / Kode', field: 'employee_code', align: 'left' },
        { name: 'user_name', label: 'Nama Lengkap', field: 'user_name', align: 'left' },
        { name: 'department', label: 'Departemen', field: 'department', align: 'left' },
        { name: 'check_in_time', label: 'Jam Masuk', field: 'check_in_time', align: 'center' },
        { name: 'check_out_time', label: 'Jam Pulang', field: 'check_out_time', align: 'center' },
        { name: 'check_in_match_score', label: 'Skor Jarak Wajah', field: 'check_in_match_score', align: 'center' },
        { name: 'status', label: 'Status', field: 'status', align: 'center' }
      ]
    }
  },
  mounted () {
    this.fetchData()
  },
  methods: {
    async fetchData () {
      this.loading = true
      try {
        const res = await this.$api.get('/attendance/admin-overview')
        this.summary = res.data.data.summary
        this.records = res.data.data.records || []
      } catch (e) {
        // Handle error
      } finally {
        this.loading = false
      }
    }
  }
}
</script>

