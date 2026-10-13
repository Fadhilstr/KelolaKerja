// Face Vector Extraction & 3D 68-Landmark Liveness Helper
// Uses @vladmandic/face-api (ResNet-34 128-D Face Recognition + 68 Point Facial Landmark Net)

let modelsLoaded = false

export async function ensureFaceModelsLoaded () {
  if (modelsLoaded) return true
  if (!window.faceapi) {
    throw new Error('Library Neural Network face-api.js belum termuat.')
  }
  await Promise.all([
    window.faceapi.nets.tinyFaceDetector.loadFromUri('/models'),
    window.faceapi.nets.faceLandmark68Net.loadFromUri('/models'),
    window.faceapi.nets.faceRecognitionNet.loadFromUri('/models'),
    window.faceapi.nets.faceExpressionNet.loadFromUri('/models')
  ])
  modelsLoaded = true
  return true
}

export async function extractFaceEmbeddingFromCanvas (videoElement) {
  await ensureFaceModelsLoaded()
  const options = new window.faceapi.TinyFaceDetectorOptions({
    inputSize: 320,
    scoreThreshold: 0.55
  })
  const detections = await window.faceapi
    .detectAllFaces(videoElement, options)
    .withFaceLandmarks()
    .withFaceExpressions()
    .withFaceDescriptors()

  if (!detections || detections.length === 0) {
    throw new Error('Wajah tidak terdeteksi di kamera.')
  }
  if (detections.length > 1) {
    throw new Error('Terdeteksi lebih dari 1 wajah di kamera. Hanya 1 wajah yang diizinkan.')
  }

  return Array.from(detections[0].descriptor)
}

export function compute3DLandmarkMetrics (landmarks, expressions) {
  const pts = landmarks.positions
  const jawWidth = Math.max(1.0, pts[16].x - pts[0].x)
  const noseYawRatio = (pts[30].x - pts[0].x) / jawWidth
  const yawOffset = Math.abs(noseYawRatio - 0.50)

  const mouthWidth = Math.max(1.0, Math.hypot(pts[54].x - pts[48].x, pts[54].y - pts[48].y))
  const mouthOpen = Math.hypot(pts[66].x - pts[62].x, pts[66].y - pts[62].y)
  const mar = mouthOpen / mouthWidth
  const happyScore = (expressions && expressions.happy) ? expressions.happy : 0

  return {
    noseYawRatio,
    yawOffset,
    mar,
    happyScore
  }
}
