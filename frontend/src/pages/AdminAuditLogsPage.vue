<template>
  <q-page class="q-pa-md">
    <div class="text-h6 text-weight-bold q-mb-md">Audit Log & Jejak Keamanan</div>

    <q-card class="shadow-1">
      <q-table
        :data="logs"
        :columns="columns"
        row-key="id"
        :loading="loading"
        no-data-label="Belum ada catatan audit log."
      >
        <template v-slot:body-cell-status="props">
          <q-td :props="props">
            <q-badge :color="props.value === 'SUCCESS' ? 'positive' : (props.value === 'DENIED' ? 'warning' : 'negative')">
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
  name: 'AdminAuditLogsPage',
  data () {
    return {
      logs: [],
      loading: false,
      columns: [
        { name: 'created_at', label: 'Waktu Server', field: 'created_at', align: 'left', sortable: true },
        { name: 'username', label: 'Pengguna', field: 'username', align: 'left' },
        { name: 'action', label: 'Aksi Tindakan', field: 'action', align: 'left' },
        { name: 'resource_type', label: 'Entitas', field: 'resource_type', align: 'left' },
        { name: 'ip_address', label: 'Alamat IP', field: 'ip_address', align: 'left' },
        { name: 'status', label: 'Hasil', field: 'status', align: 'center' }
      ]
    }
  },
  mounted () {
    this.fetchLogs()
  },
  methods: {
    async fetchLogs () {
      this.loading = true
      try {
        const res = await this.$api.get('/admin/audit-logs')
        this.logs = res.data.data || []
      } catch (e) {
        // Handle error
      } finally {
        this.loading = false
      }
    }
  }
}
</script>

