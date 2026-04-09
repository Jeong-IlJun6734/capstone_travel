package com.example.demo_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.PI

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "demo_app/rotation_vectors",
        ).setStreamHandler(RotationVectorStreamHandler(applicationContext))
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "demo_app/step_detector",
        ).setStreamHandler(StepDetectorStreamHandler(applicationContext))
    }
}

private class RotationVectorStreamHandler(
    context: Context,
) : EventChannel.StreamHandler, SensorEventListener {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private val geomagneticSensor =
        sensorManager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
    private val gameSensor =
        sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)

    private var events: EventChannel.EventSink? = null
    private var geomagneticAzimuth: Double? = null
    private var gameAzimuth: Double? = null

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        events = eventSink
        geomagneticSensor?.also {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_FASTEST)
        }
        gameSensor?.also {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_FASTEST)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR -> {
                geomagneticAzimuth = extractAzimuth(event.values)
            }

            Sensor.TYPE_GAME_ROTATION_VECTOR -> {
                gameAzimuth = extractAzimuth(event.values)
            }
        }

        events?.success(
            mapOf(
                "geomagneticAzimuth" to geomagneticAzimuth,
                "gameAzimuth" to gameAzimuth,
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun extractAzimuth(values: FloatArray): Double {
        val rotationMatrix = FloatArray(9)
        val orientation = FloatArray(3)
        SensorManager.getRotationMatrixFromVector(rotationMatrix, values)
        SensorManager.getOrientation(rotationMatrix, orientation)
        return normalizeAngle(orientation[0].toDouble())
    }

    private fun normalizeAngle(angle: Double): Double {
        var normalized = angle
        while (normalized <= -PI) {
            normalized += 2 * PI
        }
        while (normalized > PI) {
            normalized -= 2 * PI
        }
        return normalized
    }
}

private class StepDetectorStreamHandler(
    context: Context,
) : EventChannel.StreamHandler, SensorEventListener {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private val stepDetectorSensor =
        sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)

    private var events: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        events = eventSink
        if (stepDetectorSensor == null) {
            eventSink.success(
                mapOf(
                    "available" to false,
                    "stepDetected" to false,
                ),
            )
            return
        }

        eventSink.success(
            mapOf(
                "available" to true,
                "stepDetected" to false,
            ),
        )
        sensorManager.registerListener(
            this,
            stepDetectorSensor,
            SensorManager.SENSOR_DELAY_FASTEST,
        )
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_STEP_DETECTOR) {
            return
        }

        events?.success(
            mapOf(
                "available" to true,
                "stepDetected" to (event.values.firstOrNull() == 1.0f),
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
