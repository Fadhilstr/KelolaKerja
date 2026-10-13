module.exports = function (ctx) {
  return {
    supportTS: false,
    boot: [
      'axios'
    ],
    css: [
      'app.scss'
    ],
    extras: [
      'roboto-font',
      'material-icons'
    ],
    build: {
      vueRouterMode: 'hash',
      extendWebpack (cfg) {
        // Webpack 4 extensions
      }
    },
    devServer: {
      port: 8080,
      open: false,
      proxy: {
        '/api': {
          target: 'http://localhost:5000',
          changeOrigin: true
        }
      }
    },
    framework: {
      iconSet: 'material-icons',
      lang: 'en-us',
      config: {},
      plugins: [
        'Notify',
        'Dialog',
        'Loading'
      ]
    },
    pwa: {
      workboxPluginMode: 'GenerateSW',
      workboxOptions: {
        skipWaiting: true,
        clientsClaim: true
      },
      manifest: {
        name: 'KelolaKerja Attendance',
        short_name: 'KelolaKerja',
        description: 'Sistem Absensi dan Pelaporan Karyawan Berbasis Face Recognition',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#ffffff',
        theme_color: '#1976D2'
      }
    }
  }
}

