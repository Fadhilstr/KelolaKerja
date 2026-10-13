<template>
  <q-page class="q-pa-md">
    <div class="row justify-center">
      <div class="col-xs-12 col-md-8">
        <q-card class="shadow-1">
          <q-card-section>
            <div class="text-h6 text-weight-bold">
              <q-icon name="face" color="primary" class="q-mr-sm" />
              Pendaftaran Biometrik Wajah
            </div>
            <div class="text-caption text-grey-7">
              Daftarkan fitur biometrik wajah Anda sebagai kunci identifikasi absensi harian.
            </div>
          </q-card-section>

          <q-card-section class="column items-center">
            <div class="camera-container relative-position">
              <video ref="video" autoplay playsinline muted class="camera-feed"></video>
              <div class="face-guide-overlay"></div>
            </div>

            <div class="q-mt-md text-caption text-grey-7 text-center">
              Posisikan wajah tegak, lepas kacamata hitam atau masker, dan pastikan pencahayaan terang merata.
            </div>
          </q-card-section>

          <q-card-actions align="center" class="q-pb-md">
            <q-btn
              v-if="!cameraActive"
              color="primary"
              icon="camera_alt"
              label="Buka Kamera"
              @click="startCamera"
            />
            <q-btn
              v-else
              color="positive"
              icon="save"
              label="Ambil & Simpan Biometrik"
              @click="captureAndEnroll"
              :loading="saving"
            />
          </q-card-actions>
        </q-card>
      </div>
    </div>
  </q-page>
</template>

<script>
import { extractFaceEmbeddingFromCanvas } from 'src/services/faceService'

export default {
  name: 'BiometricEnrollmentPage',
  data () {
    return {
      cameraActive: false,
      saving: false,
      stream: null
    }
  },
  beforeDestroy () {
    this.stopCamera()
  },
  methods: {
    async startCamera () {
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({
          video: { width: 640, height: 480, facingMode: 'user' },
          audio: false
        })
        this.$refs.video.srcObject = this.stream
        this.cameraActive = true
      } catch (e) {
        this.$q.notify({
          type: 'negative',
          message: 'Izin kamera ditolak atau kamera tidak ditemukan.'
        })
      }
    },
    stopCamera () {
      if (this.stream) {
        this.stream.getTracks().forEach(t => t.stop())
        this.stream = null
      }
      this.cameraActive = false
    },
    async captureAndEnroll () {
      this.saving = true
      try {
        const embedding = extractFaceEmbeddingFromCanvas(this.$refs.video)
        const res = await this.$api.post('/biometric/register', {
          embedding: embedding,
          quality_score: 0.95
        })

        if (res.data.success) {
          this.$q.notify({
            type: 'positive',
            message: 'Biometrik wajah berhasil didaftarkan.'
          })
          this.stopCamera()
          this.$router.push('/attendance')
        }
      } catch (err) {
        const msg = (err.response && err.response.data && err.response.data.message)
          ? err.response.data.message
          : 'Gagal menyimpan biometrik wajah'
        this.$q.notify({
          type: 'negative',
          message: msg
        })
      } finally {
        this.saving = false
      }
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
</style>

