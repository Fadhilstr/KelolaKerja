<template>
  <q-page class="q-pa-md">
    <div class="text-h6 text-weight-bold q-mb-md">Dashboard Supervisi & Verifikasi</div>

    <!-- Summary Cards -->
    <div class="row q-col-gutter-md q-mb-md" v-if="summary">
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-blue-1 text-primary shadow-1">
          <q-card-section>
            <div class="text-caption">Total Karyawan</div>
            <div class="text-h5 text-weight-bolder">{{ summary.total_employees || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-green-1 text-positive shadow-1">
          <q-card-section>
            <div class="text-caption">Hadir Hari Ini</div>
            <div class="text-h5 text-weight-bolder">{{ summary.present_count || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-orange-1 text-warning shadow-1">
          <q-card-section>
            <div class="text-caption">Terlambat</div>
            <div class="text-h5 text-weight-bolder">{{ summary.late_count || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
      <div class="col-xs-12 col-sm-3">
        <q-card class="bg-red-1 text-negative shadow-1">
          <q-card-section>
            <div class="text-caption">Belum Absen</div>
            <div class="text-h5 text-weight-bolder">{{ summary.not_present_count || 0 }}</div>
          </q-card-section>
        </q-card>
      </div>
    </div>

    <!-- Reports for Approval Table -->
    <q-card class="shadow-1 q-mb-md">
      <q-card-section>
        <div class="text-subtitle1 text-weight-bold">Daftar Laporan Karyawan Menunggu Verifikasi</div>
      </q-card-section>
      <q-table
        :data="pendingReports"
        :columns="reportColumns"
        row-key="id"
        :loading="loadingReports"
        no-data-label="Tidak ada laporan yang perlu diverifikasi saat ini."
      >
        <template v-slot:body-cell-actions="props">
          <q-td :props="props">
            <q-btn size="sm" color="positive" label="Setujui" class="q-mr-xs" @click="verifyReport(props.row.id, 'APPROVED')" />
            <q-btn size="sm" color="negative" label="Tolak" @click="verifyReport(props.row.id, 'REJECTED')" />
          </q-td>
        </template>
      </q-table>
    </q-card>
  </q-page>
</template>

<script>
export default {
  name: 'SupervisorDashboardPage',
  data () {
    return {
      summary: null,
      pendingReports: [],
      loadingReports: false,
      reportColumns: [
        { name: 'report_date', label: 'Tanggal', field: 'report_date', align: 'left' },
        { name: 'employee_name', label: 'Nama Karyawan', field: 'employee_name', align: 'left' },
        { name: 'title', label: 'Tugas', field: 'title', align: 'left' },
        { name: 'activity_description', label: 'Deskripsi', field: 'activity_description', align: 'left' },
        { name: 'status', label: 'Status', field: 'status', align: 'center' },
        { name: 'actions', label: 'Aksi', align: 'center' }
      ]
    }
  },
  mounted () {
    this.fetchOverview()
    this.fetchPendingReports()
  },
  methods: {
    async fetchOverview () {
      try {
        const res = await this.$api.get('/attendance/admin-overview')
        this.summary = res.data.data.summary
      } catch (e) {
        // Handle error
      }
    },
    async fetchPendingReports () {
      this.loadingReports = true
      try {
        const res = await this.$api.get('/reports', { params: { status: 'SUBMITTED' } })
        this.pendingReports = res.data.data.reports || []
      } catch (e) {
        // Handle error
      } finally {
        this.loadingReports = false
      }
    },
    async verifyReport (id, status) {
      try {
        await this.$api.post(`/reports/${id}/verify`, { status: status, verification_notes: `Diverifikasi oleh supervisor` })
        this.$q.notify({ type: 'positive', message: `Laporan berhasil di-${status.toLowerCase()}` })
        await this.fetchPendingReports()
      } catch (e) {
        this.$q.notify({ type: 'negative', message: 'Gagal memproses verifikasi laporan' })
      }
    }
  }
}
</script>

