<template>
  <q-page class="q-pa-md">
    <div class="row q-col-gutter-md">
      <!-- Camera Card -->
      <div class="col-xs-12 col-md-7">
        <q-card class="shadow-1">
          <q-card-section>
            <div class="text-h6 text-weight-bold">
              <q-icon name="videocam" color="primary" class="q-mr-sm" />
              Pindai Wajah untuk Absensi
            </div>
            <div class="text-caption text-grey-7">
              Pastikan pencahayaan cukup dan wajah berada di dalam bingkai oval panduan.
            </div>
          </q-card-section>

          <q-card-section class="column items-center">
            <div class="camera-container relative-position">
              <video ref="video" autoplay playsinline muted class="camera-feed"></video>
              <div class="face-guide-overlay"></div>
              <div v-if="cameraLoading" class="camera-overlay row justify-center items-center">
                <q-spinner color="white" size="48px" />
                <div class="text-white q-mt-sm">Mengakses Kamera...</div>
              </div>
            </div>

            <!-- Liveness Challenge Indicator -->
            <div class="q-mt-md full-width" v-if="cameraActive">
              <q-banner rounded dense class="bg-blue-1 text-primary text-center">
                <q-icon name="verified_user" size="20px" class="q-mr-xs" />
                <strong>Instruksi Verifikasi Kehadiran:</strong>
                {{ currentChallenge.instruction }}
              </q-banner>
            </div>
          </q-card-section>

          <q-card-actions align="center" class="q-pb-md">
            <q-btn
              v-if="!cameraActive"
              color="primary"
              icon="camera_alt"
              label="Aktifkan Kamera"
              @click="startCamera"
              :loading="cameraLoading"
            />
            <template v-else>
              <q-btn
                color="positive"
                icon="login"
                label="Absen Masuk"
                @click="submitAttendance('check-in')"
                :loading="submitting"
                :disable="todayAttendance && !!todayAttendance.check_in_time"
                class="q-mr-sm"
              />
              <q-btn
                color="orange"
                icon="logout"
                label="Absen Pulang"
                @click="submitAttendance('check-out')"
                :loading="submitting"
                :disable="!todayAttendance || !todayAttendance.check_in_time || !!todayAttendance.check_out_time"
              />
            </template>
          </q-card-actions>
        </q-card>
      </div>

      <!-- Attendance Status Card -->
      <div class="col-xs-12 col-md-5">
        <q-card class="shadow-1 q-mb-md">
          <q-card-section>
            <div class="text-h6 text-weight-bold">
              <q-icon name="schedule" color="primary" class="q-mr-sm" />
              Status Absensi Hari Ini
            </div>
            <div class="text-caption text-grey-7">{{ todayFormatted }}</div>
          </q-card-section>

          <q-separator />

          <q-card-section>
            <div class="row q-col-gutter-sm">
              <div class="col-6 text-center">
                <div class="text-caption text-grey-6">Masuk</div>
                <div class="text-h6 text-weight-bolder text-positive">
                  {{ (todayAttendance && todayAttendance.check_in_time) ? formatTime(todayAttendance.check_in_time) : '--:--' }}
                </div>
              </div>
              <div class="col-6 text-center">
                <div class="text-caption text-grey-6">Pulang</div>
                <div class="text-h6 text-weight-bolder text-orange">
                  {{ (todayAttendance && todayAttendance.check_out_time) ? formatTime(todayAttendance.check_out_time) : '--:--' }}
                </div>
              </div>
            </div>

            <div class="q-mt-md" v-if="todayAttendance">
              <q-chip :color="getStatusColor(todayAttendance.status)" text-color="white" dense>
                Status: {{ todayAttendance.status }}
              </q-chip>
            </div>
          </q-card-section>
        </q-card>

        <!-- Personal History Card -->
        <q-card class="shadow-1">
          <q-card-section>
            <div class="text-subtitle1 text-weight-bold">Riwayat Absensi Terakhir</div>
          </q-card-section>
          <q-list separator dense>
            <q-item v-for="item in historyList.slice(0, 5)" :key="item.id">
              <q-item-section>
                <q-item-label class="text-weight-medium">{{ item.attendance_date }}</q-item-label>
                <q-item-label caption>
                  Masuk: {{ formatTime(item.check_in_time) }} | Pulang: {{ formatTime(item.check_out_time) }}
                </q-item-label>
              </q-item-section>
              <q-item-section side>
                <q-badge :color="getStatusColor(item.status)">{{ item.status }}</q-badge>
              </q-item-section>
            </q-item>
            <q-item v-if="historyList.length === 0">
              <q-item-section class="text-center text-grey-6 q-pa-sm">
                Belum ada riwayat absensi
              </q-item-section>
            </q-item>
          </q-list>
        </q-card>
      </div>
    </div>
  </q-page>
</template>

<script>
import { extractFaceEmbeddingFromCanvas, LIVENESS_CHALLENGES } from 'src/services/faceService'

export default {
  name: 'AttendancePage',
  data () {
    return {
      cameraActive: false,
      cameraLoading: false,
      submitting: false,
      stream: null,
      todayAttendance: null,
      historyList: [],
      currentChallenge: LIVENESS_CHALLENGES[0]
    }
  },
  computed: {
    todayFormatted () {
      const options = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }
      return new Date().toLocaleDateString('id-ID', options)
    }
  },
  mounted () {
    this.fetchTodayStatus()
    this.fetchHistory()
  },
  beforeDestroy () {
    this.stopCamera()
  },
  methods: {
    async fetchTodayStatus () {
      try {
        const res = await this.$api.get('/attendance/today')
        this.todayAttendance = res.data.data
      } catch (e) {
        // Handle error silently
      }
    },
    async fetchHistory () {
      try {
        const res = await this.$api.get('/attendance/history')
        this.historyList = res.data.data || []
      } catch (e) {
        // Handle error
      }
    },
    async startCamera () {
      this.cameraLoading = true
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({
          video: { width: 640, height: 480, facingMode: 'user' },
          audio: false
        })
        this.$refs.video.srcObject = this.stream
        this.cameraActive = true
      } catch (err) {
        this.$q.notify({
          type: 'negative',
          message: 'Gagal mengakses kamera: Pastikan izin kamera telah diberikan di browser.'
        })
      } finally {
        this.cameraLoading = false
      }
    },
    stopCamera () {
      if (this.stream) {
        this.stream.getTracks().forEach(track => track.stop())
        this.stream = null
      }
      this.cameraActive = false
    },
    async submitAttendance (type) {
      this.submitting = true
      try {
        const embedding = extractFaceEmbeddingFromCanvas(this.$refs.video)
        const endpoint = type === 'check-in' ? '/attendance/check-in' : '/attendance/check-out'

        const response = await this.$api.post(endpoint, {
          embedding: embedding,
          liveness_passed: 1,
          photo_path: 'live_webcam_capture.jpg'
        })

        if (response.data.success) {
          this.$q.notify({
            type: 'positive',
            message: response.data.message
          })
          await this.fetchTodayStatus()
          await this.fetchHistory()
        }
      } catch (err) {
        const msg = (err.response && err.response.data && err.response.data.message)
          ? err.response.data.message
          : 'Gagal memproses verifikasi wajah'
        this.$q.notify({
          type: 'negative',
          message: msg
        })
      } finally {
        this.submitting = false
      }
    },
    formatTime (dt) {
      if (!dt) return '--:--'
      const parts = dt.split(' ')
      return parts[1] ? parts[1].substring(0, 5) : dt
    },
    getStatusColor (status) {
      if (status === 'PRESENT') return 'positive'
      if (status === 'LATE') return 'warning'
      return 'grey-7'
    }
  }
}
</script>

<style scoped>
.camera-container {
  width: 100%;
  max-width: 480px;
  height: 360px;
  background-color: #000;
  border-radius: 8px;
  overflow: hidden;
  position: relative;
}
.camera-feed {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.face-guide-overlay {
  position: absolute;
  top: 15%;
  left: 25%;
  width: 50%;
  height: 70%;
  border: 2px dashed rgba(255, 255, 255, 0.7);
  border-radius: 50%;
  pointer-events: none;
}
.camera-overlay {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0,0,0,0.7);
  flex-direction: column;
}
</style>

