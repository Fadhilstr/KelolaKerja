<template>
  <div class="fullscreen bg-red-1 text-negative text-center q-pa-md flex flex-center">
    <div>
      <div style="font-size: 15vh">403</div>
      <div class="text-h4" style="opacity:.6">Akses Ditolak (Unauthorized)</div>
      <div class="text-subtitle1 q-mt-md">Anda tidak memiliki hak akses yang cukup untuk melihat halaman ini.</div>
      <q-btn class="q-mt-xl" color="negative" to="/" label="Kembali ke Dashboard Utama" no-caps />
    </div>
  </div>
</template>

<script>
export default {
  name: 'UnauthorizedPage'
}
</script>

