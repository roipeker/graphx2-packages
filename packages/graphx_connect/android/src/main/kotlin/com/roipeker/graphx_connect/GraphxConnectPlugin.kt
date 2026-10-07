package com.roipeker.graphx_connect

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.nio.charset.StandardCharsets

class GraphxConnectPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var appContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val instances = mutableMapOf<String, NearbyInstance>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        instances.values.forEach { it.dispose() }
        instances.clear()
        eventSink = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> create(call, result)
            "prepare" -> prepare(result)

            "startAdvertising" -> withInstance(call, result) { instance ->
                val context = call.argument<ByteArray>("context")
                    ?: return@withInstance result.error("bad_args", "Missing context.", null)
                instance.startAdvertising(context, result)
            }

            "stopAdvertising" -> withInstance(call, result) { instance ->
                instance.stopAdvertising()
                result.success(null)
            }

            "startDiscovery" -> withInstance(call, result) { instance ->
                instance.startDiscovery(result)
            }

            "stopDiscovery" -> withInstance(call, result) { instance ->
                instance.stopDiscovery()
                result.success(null)
            }

            "requestConnection" -> withInstance(call, result) { instance ->
                val endpointId = call.argument<String>("endpointId")
                    ?: return@withInstance result.error("bad_args", "Missing endpointId.", null)
                instance.requestConnection(endpointId, result)
            }

            "send" -> withInstance(call, result) { instance ->
                val endpointId = call.argument<String>("endpointId")
                    ?: return@withInstance result.error("bad_args", "Missing endpointId.", null)
                val data = call.argument<ByteArray>("data")
                    ?: return@withInstance result.error("bad_args", "Missing data.", null)
                instance.send(endpointId, data, result)
            }

            "disconnect" -> withInstance(call, result) { instance ->
                val endpointId = call.argument<String>("endpointId")
                    ?: return@withInstance result.error("bad_args", "Missing endpointId.", null)
                instance.disconnect(endpointId)
                result.success(null)
            }

            "dispose" -> {
                val id = call.argument<String>("instanceId")
                if (id == null) {
                    result.error("bad_args", "Missing instanceId.", null)
                    return
                }
                instances.remove(id)?.dispose()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("instanceId")
        val serviceId = call.argument<String>("serviceId")
        if (id.isNullOrBlank() || serviceId.isNullOrBlank()) {
            result.error("bad_args", "Missing nearby instance configuration.", null)
            return
        }

        instances.remove(id)?.dispose()
        instances[id] = NearbyInstance(
            appContext,
            id,
            serviceId,
            ::emit,
        )
        result.success(null)
    }

    private fun prepare(result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            appContext.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(null)
            return
        }

        val activity = activityBinding?.activity
        if (activity == null) {
            result.error(
                "no_activity",
                "Nearby runtime permissions require an attached Android Activity.",
                null,
            )
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                "permission_busy",
                "A Nearby permission request is already active.",
                null,
            )
            return
        }

        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = pendingPermissionResult ?: return false
        pendingPermissionResult = null

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (granted) {
            result.success(null)
        } else {
            result.error(
                "permission_denied",
                "Nearby Connections requires the requested Bluetooth/Wi-Fi permissions.",
                permissions.toList(),
            )
        }
        return true
    }

    private fun requiredPermissions(): List<String> {
        val sdk = Build.VERSION.SDK_INT
        val permissions = mutableListOf<String>()

        when {
            sdk <= 28 -> {
                permissions += "android.permission.ACCESS_COARSE_LOCATION"
            }

            sdk <= 30 -> {
                permissions += "android.permission.ACCESS_FINE_LOCATION"
            }

            sdk == 31 -> {
                permissions += "android.permission.ACCESS_FINE_LOCATION"
                permissions += "android.permission.BLUETOOTH_ADVERTISE"
                permissions += "android.permission.BLUETOOTH_CONNECT"
                permissions += "android.permission.BLUETOOTH_SCAN"
            }

            else -> {
                permissions += "android.permission.BLUETOOTH_ADVERTISE"
                permissions += "android.permission.BLUETOOTH_CONNECT"
                permissions += "android.permission.BLUETOOTH_SCAN"

                if (sdk >= 33) {
                    permissions += "android.permission.NEARBY_WIFI_DEVICES"
                }
                if (sdk >= 37) {
                    permissions += "android.permission.ACCESS_LOCAL_NETWORK"
                }
            }
        }
        return permissions
    }

    private inline fun withInstance(
        call: MethodCall,
        result: MethodChannel.Result,
        block: (NearbyInstance) -> Unit,
    ) {
        val id = call.argument<String>("instanceId")
        val instance = id?.let(instances::get)
        if (instance == null) {
            result.error(
                "unknown_instance",
                "Nearby instance is not active.",
                null,
            )
            return
        }
        block(instance)
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "graphx_connect/nearby/methods"
        private const val EVENT_CHANNEL = "graphx_connect/nearby/events"
        private const val PERMISSION_REQUEST = 0x4758
    }
}

private class NearbyInstance(
    context: Context,
    private val instanceId: String,
    private val serviceId: String,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val client: ConnectionsClient = Nearby.getConnectionsClient(context)
    private val strategy = Strategy.P2P_POINT_TO_POINT

    private var advertisedContext: ByteArray? = null
    private var shouldAdvertise = false
    private var advertising = false
    private var discovering = false
    private var activeEndpointId: String? = null

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type != Payload.Type.BYTES) return
            val bytes = payload.asBytes() ?: return
            event("payload", endpointId, mapOf("data" to bytes))
        }

        override fun onPayloadTransferUpdate(
            endpointId: String,
            update: PayloadTransferUpdate,
        ) {
            if (update.status == PayloadTransferUpdate.Status.FAILURE) {
                event(
                    "error",
                    endpointId,
                    mapOf("message" to "Nearby payload transfer failed."),
                )
            }
        }
    }

    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            val active = activeEndpointId
            if (active != null && active != endpointId) {
                client.rejectConnection(endpointId)
                return
            }

            activeEndpointId = endpointId
            client.acceptConnection(endpointId, payloadCallback)
                .addOnFailureListener { error ->
                    if (activeEndpointId == endpointId) activeEndpointId = null
                    failConnection(endpointId, error)
                    restartAdvertisingIfNeeded()
                }
        }

        override fun onConnectionResult(
            endpointId: String,
            resolution: ConnectionResolution,
        ) {
            if (resolution.status.statusCode == CommonStatusCodes.SUCCESS) {
                activeEndpointId = endpointId

                // Discovery/advertising are radio-expensive. Once the direct
                // point-to-point link exists they are no longer useful.
                if (discovering) {
                    client.stopDiscovery()
                    discovering = false
                }
                if (advertising) {
                    client.stopAdvertising()
                    advertising = false
                }
                event("connected", endpointId)
            } else {
                if (activeEndpointId == endpointId) activeEndpointId = null
                event(
                    "connectionFailed",
                    endpointId,
                    mapOf(
                        "message" to
                            "Nearby connection failed: ${resolution.status.statusCode}",
                    ),
                )
                restartAdvertisingIfNeeded()
            }
        }

        override fun onDisconnected(endpointId: String) {
            if (activeEndpointId == endpointId) activeEndpointId = null
            event("disconnected", endpointId)
            restartAdvertisingIfNeeded()
        }
    }

    private val discoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(
            endpointId: String,
            info: DiscoveredEndpointInfo,
        ) {
            event(
                "found",
                endpointId,
                mapOf("context" to info.endpointInfo),
            )
        }

        override fun onEndpointLost(endpointId: String) {
            event("lost", endpointId)
        }
    }

    fun startAdvertising(context: ByteArray, result: MethodChannel.Result) {
        advertisedContext = context
        shouldAdvertise = true

        val options = AdvertisingOptions.Builder().setStrategy(strategy).build()
        client.startAdvertising(context, serviceId, lifecycle, options)
            .addOnSuccessListener {
                advertising = true
                result.success(null)
            }
            .addOnFailureListener { error ->
                advertising = false
                result.error("advertise_failed", error.message, null)
            }
    }

    fun stopAdvertising() {
        shouldAdvertise = false
        advertisedContext = null
        if (advertising) {
            client.stopAdvertising()
            advertising = false
        }
    }

    fun startDiscovery(result: MethodChannel.Result) {
        val options = DiscoveryOptions.Builder().setStrategy(strategy).build()
        client.startDiscovery(serviceId, discoveryCallback, options)
            .addOnSuccessListener {
                discovering = true
                result.success(null)
            }
            .addOnFailureListener { error ->
                discovering = false
                result.error("discovery_failed", error.message, null)
            }
    }

    fun stopDiscovery() {
        if (!discovering) return
        client.stopDiscovery()
        discovering = false
    }

    fun requestConnection(endpointId: String, result: MethodChannel.Result) {
        val endpointInfo = GRAPHX_ENDPOINT_INFO.toByteArray(StandardCharsets.UTF_8)
        client.requestConnection(endpointInfo, endpointId, lifecycle)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { error ->
                if (activeEndpointId == endpointId) activeEndpointId = null
                failConnection(endpointId, error)
                result.error("connect_failed", error.message, null)
            }
    }

    fun send(endpointId: String, data: ByteArray, result: MethodChannel.Result) {
        if (data.size > ConnectionsClient.MAX_BYTES_DATA_SIZE) {
            result.error(
                "payload_too_large",
                "Nearby byte payload exceeds ${ConnectionsClient.MAX_BYTES_DATA_SIZE} bytes.",
                data.size,
            )
            return
        }

        client.sendPayload(endpointId, Payload.fromBytes(data))
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { error ->
                event(
                    "error",
                    endpointId,
                    mapOf("message" to (error.message ?: "Send failed.")),
                )
                result.error("send_failed", error.message, null)
            }
    }

    fun disconnect(endpointId: String) {
        client.disconnectFromEndpoint(endpointId)
    }

    fun dispose() {
        shouldAdvertise = false
        advertisedContext = null
        activeEndpointId = null

        if (advertising) client.stopAdvertising()
        if (discovering) client.stopDiscovery()
        advertising = false
        discovering = false
        client.stopAllEndpoints()
    }

    private fun restartAdvertisingIfNeeded() {
        val context = advertisedContext ?: return
        if (!shouldAdvertise || advertising) return

        val options = AdvertisingOptions.Builder().setStrategy(strategy).build()
        client.startAdvertising(context, serviceId, lifecycle, options)
            .addOnSuccessListener {
                advertising = true
            }
            .addOnFailureListener { error ->
                advertising = false
                event(
                    "error",
                    null,
                    mapOf(
                        "message" to
                            (error.message ?: "Failed to resume advertising."),
                    ),
                )
            }
    }

    private fun failConnection(endpointId: String, error: Exception) {
        event(
            "connectionFailed",
            endpointId,
            mapOf("message" to (error.message ?: "Nearby connection failed.")),
        )
    }

    private fun event(
        type: String,
        endpointId: String? = null,
        extra: Map<String, Any?> = emptyMap(),
    ) {
        val event = mutableMapOf<String, Any?>(
            "instanceId" to instanceId,
            "type" to type,
        )
        if (endpointId != null) event["endpointId"] = endpointId
        event.putAll(extra)
        emit(event)
    }

    companion object {
        private const val GRAPHX_ENDPOINT_INFO = "graphx"
    }
}
