<template>
  <q-page class="q-pa-md">
    <div class="row justify-between items-center q-mb-md">
      <div>
        <div class="text-h6 text-weight-bold">Laporan Aktivitas Harian</div>
        <div class="text-caption text-grey-7">Catat hasil kerja dan kendala yang dihadapi untuk diverifikasi supervisor.</div>
      </div>
      <q-btn color="primary" icon="add" label="Tulis Laporan Baru" @click="openDialog" />
    </div>

    <!-- Reports Table / List -->
    <q-card class="shadow-1">
      <q-table
        :data="reports"
        :columns="columns"
        row-key="id"
        :loading="loading"
        no-data-label="Belum ada laporan aktivitas yang diajukan."
      >
        <template v-slot:body-cell-status="props">
          <q-td :props="props">
            <q-badge :color="getStatusColor(props.value)">{{ props.value }}</q-badge>
          </q-td>
        </template>
      </q-table>
    </q-card>

    <!-- New Report Dialog -->
    <q-dialog v-model="dialogOpen">
      <q-card style="min-width: 400px; max-width: 600px;">
        <q-card-section>
          <div class="text-h6">Laporan Aktivitas Pekerjaan</div>
        </q-card-section>

        <q-card-section class="q-pt-none">
          <q-input v-model="form.title" label="Judul Pekerjaan / Tugas" outlined dense class="q-mb-sm" />
          <q-input v-model="form.activity_description" label="Deskripsi Pekerjaan" type="textarea" outlined dense class="q-mb-sm" />
          <q-input v-model="form.results_achieved" label="Hasil yang Dicapai (Opsional)" type="textarea" outlined dense class="q-mb-sm" />
          <q-input v-model="form.obstacles" label="Kendala / Hambatan (Opsional)" type="textarea" outlined dense />
        </q-card-section>

        <q-card-actions align="right">
          <q-btn flat label="Batal" color="grey" v-close-popup />
          <q-btn label="Kirim Laporan" color="primary" @click="submitReport" :loading="submitting" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script>
export default {
  name: 'ReportsPage',
  data () {
    return {
      reports: [],
      loading: false,
      dialogOpen: false,
      submitting: false,
      form: {
        title: '',
        activity_description: '',
        results_achieved: '',
        obstacles: ''
      },
      columns: [
        { name: 'report_date', label: 'Tanggal', field: 'report_date', align: 'left', sortable: true },
        { name: 'title', label: 'Judul Tugas', field: 'title', align: 'left' },
        { name: 'activity_description', label: 'Deskripsi', field: 'activity_description', align: 'left' },
        { name: 'status', label: 'Status', field: 'status', align: 'center' }
      ]
    }
  },
  mounted () {
    this.fetchReports()
  },
  methods: {
    async fetchReports () {
      this.loading = true
      try {
        const res = await this.$api.get('/reports')
        this.reports = res.data.data.reports || []
      } catch (e) {
        // Handle error
      } finally {
        this.loading = false
      }
    },
    openDialog () {
      this.form = { title: '', activity_description: '', results_achieved: '', obstacles: '' }
      this.dialogOpen = true
    },
    async submitReport () {
      if (!this.form.title || !this.form.activity_description) {
        this.$q.notify({ type: 'warning', message: 'Judul dan deskripsi wajib diisi' })
        return
      }

      this.submitting = true
      try {
        const res = await this.$api.post('/reports', this.form)
        if (res.data.success) {
          this.$q.notify({ type: 'positive', message: 'Laporan berhasil diajukan' })
          this.dialogOpen = false
          await this.fetchReports()
        }
      } catch (e) {
        this.$q.notify({ type: 'negative', message: 'Gagal mengirim laporan' })
      } finally {
        this.submitting = false
      }
    },
    getStatusColor (status) {
      if (status === 'APPROVED') return 'positive'
      if (status === 'REJECTED') return 'negative'
      return 'primary'
    }
  }
}
</script>

