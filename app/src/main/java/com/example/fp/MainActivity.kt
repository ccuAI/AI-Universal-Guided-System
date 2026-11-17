package com.example.fp

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.example.fp.ui.theme.FpTheme
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException

// -----------------------------------------------------------------
// 1. 資料類別
// -----------------------------------------------------------------
data class MedicalPlace(
    val name: String,
    val phone: String,
    val rating: Double?,
    val userRatingCount: Int?,
    val lat: Double,
    val lng: Double,
    val address: String,
    val openNow: Boolean?
)

// -----------------------------------------------------------------
// 2. 13 大醫療科別選單項目
// -----------------------------------------------------------------
val MEDICAL_CATEGORIES = listOf(
    "🏥 全部醫療院所",
    "🩺 內科",
    "🔪 外科",
    "🍼 小兒科",
    "👶 婦產科",
    "👂 耳鼻喉科",
    "👁️ 眼科",
    "✨ 皮膚科",
    "🦴 骨科",
    "💪 復健科",
    "🦷 牙科",
    "🌿 中醫科",
    "🧠 精神/身心科",
    "💊 藥局"
)

// -----------------------------------------------------------------
// 3. 自動取得裝置目前定位經緯度 (FusedLocationProviderClient)
// -----------------------------------------------------------------
fun getCurrentLocation(
    context: Context,
    onLocationFetched: (Double, Double) -> Unit,
    onError: (String) -> Unit
) {
    val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)

    val hasFineLocation = ContextCompat.checkSelfPermission(
        context, Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    val hasCoarseLocation = ContextCompat.checkSelfPermission(
        context, Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    if (!hasFineLocation && !hasCoarseLocation) {
        onError("未取得定位權限")
        return
    }

    try {
        val cancellationTokenSource = CancellationTokenSource()
        fusedLocationClient.getCurrentLocation(
            Priority.PRIORITY_HIGH_ACCURACY,
            cancellationTokenSource.token
        ).addOnSuccessListener { location: Location? ->
            if (location != null) {
                onLocationFetched(location.latitude, location.longitude)
            } else {
                fusedLocationClient.lastLocation.addOnSuccessListener { lastLoc: Location? ->
                    if (lastLoc != null) {
                        onLocationFetched(lastLoc.latitude, lastLoc.longitude)
                    } else {
                        onError("無法取得定位，請確認手機 GPS 已開啟")
                    }
                }
            }
        }.addOnFailureListener { e ->
            onError("定位失敗：${e.message}")
        }
    } catch (e: SecurityException) {
        onError("定位權限錯誤：${e.message}")
    }
}

// -----------------------------------------------------------------
// 4. 跳轉開啟 Google Maps 導航函式
// -----------------------------------------------------------------
fun launchNavigation(context: Context, lat: Double, lng: Double, placeName: String) {
    val gmmIntentUri = Uri.parse("google.navigation:q=$lat,$lng")
    val mapIntent = Intent(Intent.ACTION_VIEW, gmmIntentUri).apply {
        setPackage("com.google.android.apps.maps")
    }

    try {
        context.startActivity(mapIntent)
    } catch (e: Exception) {
        val browserUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng")
        val browserIntent = Intent(Intent.ACTION_VIEW, browserUri)
        context.startActivity(browserIntent)
    }
}

// -----------------------------------------------------------------
// 5. 利用 Places API (New) 的 Text Search 抓取前 20 筆結果
// -----------------------------------------------------------------
fun fetchNearbyMedicalPlaces(
    userLat: Double,
    userLng: Double,
    selectedCategory: String,
    apiKey: String,
    onSuccess: (List<MedicalPlace>) -> Unit,
    onError: (String) -> Unit
) {
    val url = "https://places.googleapis.com/v1/places:searchText"

    try {
        val cleanKeyword = selectedCategory.replace(Regex("[^\\u4e00-\\u9fa5]"), "").trim()
        val queryText = if (cleanKeyword == "全部醫療院所") "醫療院所 診所 醫院" else cleanKeyword

        val jsonRequestBody = JSONObject().apply {
            put("textQuery", queryText)
            put("maxResultCount", 20)

            val center = JSONObject().apply {
                put("latitude", userLat)
                put("longitude", userLng)
            }
            val circle = JSONObject().apply {
                put("center", center)
                put("radius", 15000.0)
            }
            val locationBias = JSONObject().apply {
                put("circle", circle)
            }
            put("locationBias", locationBias)
        }

        val mediaType = "application/json; charset=utf-8".toMediaType()
        val body = jsonRequestBody.toString().toRequestBody(mediaType)

        val request = Request.Builder()
            .url(url)
            .post(body)
            .addHeader("Content-Type", "application/json")
            .addHeader("X-Goog-Api-Key", apiKey)
            .addHeader("X-Goog-Language-Code", "zh-TW")
            .addHeader(
                "X-Goog-FieldMask",
                "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.nationalPhoneNumber,places.currentOpeningHours.openNow"
            )
            .build()

        val client = OkHttpClient()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e("MedicalFetch", "網路請求失敗: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    onError("連線失敗：${e.message}")
                }
            }

            override fun onResponse(call: Call, response: Response) {
                val responseData = response.body?.string() ?: ""
                Log.d("MedicalFetch", "HTTP Status: ${response.code}")

                if (!response.isSuccessful) {
                    Handler(Looper.getMainLooper()).post {
                        onError("API 錯誤 (HTTP ${response.code})：$responseData")
                    }
                    return
                }

                try {
                    val jsonObject = JSONObject(responseData)
                    val placesArray = jsonObject.optJSONArray("places")
                    val medicalPlacesList = mutableListOf<MedicalPlace>()

                    if (placesArray != null) {
                        for (i in 0 until placesArray.length()) {
                            val item = placesArray.getJSONObject(i)

                            val name = item.optJSONObject("displayName")?.optString("text", "未知名稱") ?: "未知名稱"
                            val address = item.optString("formattedAddress", "無地址資料")

                            if (name.contains("AED") || name.contains("急救箱")) {
                                continue
                            }

                            val phone = item.optString("nationalPhoneNumber", "未提供電話")
                            val rating = if (item.has("rating")) item.getDouble("rating") else null
                            val userRatingCount = if (item.has("userRatingCount")) item.getInt("userRatingCount") else null

                            val locObj = item.optJSONObject("location")
                            val pLat = locObj?.optDouble("latitude", 0.0) ?: 0.0
                            val pLng = locObj?.optDouble("longitude", 0.0) ?: 0.0

                            val openNow = item.optJSONObject("currentOpeningHours")?.optBoolean("openNow")

                            medicalPlacesList.add(
                                MedicalPlace(
                                    name = name,
                                    phone = phone,
                                    rating = rating,
                                    userRatingCount = userRatingCount,
                                    lat = pLat,
                                    lng = pLng,
                                    address = address,
                                    openNow = openNow
                                )
                            )
                        }
                    }

                    Handler(Looper.getMainLooper()).post {
                        onSuccess(medicalPlacesList)
                    }
                } catch (e: Exception) {
                    Log.e("MedicalFetch", "JSON 解析失敗: ${e.message}")
                    Handler(Looper.getMainLooper()).post {
                        onError("解析失敗：${e.message}")
                    }
                }
            }
        })
    } catch (e: Exception) {
        onError("建立請求失敗：${e.message}")
    }
}

// -----------------------------------------------------------------
// 6. 浮點／懸浮卡片元件 (點擊展開詳細資訊與導航)
// -----------------------------------------------------------------
@Composable
fun MedicalPlaceCard(
    place: MedicalPlace,
    onNavigateClick: () -> Unit
) {
    var isExpanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .clickable { isExpanded = !isExpanded }
            .animateContentSize(
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioLowBouncy,
                    stiffness = Spring.StiffnessLow
                )
            ),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            // 卡片主要標題與簡短資訊（診所名稱與地址）
            Text(
                text = "🏥 ${place.name}",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "📍 ${place.address}",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f)
            )

            // 💡 點擊後展開顯示詳細內容（電話、評分、營業狀態）
            AnimatedVisibility(visible = isExpanded) {
                Column(modifier = Modifier.padding(top = 12.dp)) {
                    val ratingStr = if (place.rating != null) "${place.rating} ★ (${place.userRatingCount ?: 0}則評價)" else "無評分"
                    val statusStr = if (place.openNow == true) "營業中" else if (place.openNow == false) "已休息" else "未知"

                    Text(text = "📞 電話：${place.phone}", fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(text = "⭐ 評分：$ratingStr", fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(text = "🕒 狀態：$statusStr", fontSize = 14.sp)
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // 💡 下方導航按鈕
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Button(
                    onClick = onNavigateClick,
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text(text = "🗺️ 前往導航")
                }
            }
        }
    }
}

// -----------------------------------------------------------------
// 7. Activity 主程式
// -----------------------------------------------------------------
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            FpTheme {
                FpApp()
            }
        }
    }
}

enum class AppDestinations(
    val label: String,
    val icon: Int
) {
    HOME("Home", R.drawable.ic_home),
    FAVORITES("Favorites", R.drawable.ic_favorite),
    PROFILE("Profile", R.drawable.ic_account_box)
}

// -----------------------------------------------------------------
// 8. Compose UI 畫面
// -----------------------------------------------------------------
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FpApp() {
    val context = LocalContext.current

    var currentDestination by rememberSaveable { mutableStateOf(AppDestinations.HOME) }

    var latVal by remember { mutableStateOf(23.559) }
    var lngVal by remember { mutableStateOf(120.472) }

    val myApiKey = "APIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII"

    var expanded by remember { mutableStateOf(false) }
    var selectedCategory by remember { mutableStateOf(MEDICAL_CATEGORIES[0]) }

    var placesList by remember { mutableStateOf<List<MedicalPlace>>(emptyList()) }
    var resultStatusText by remember { mutableStateOf("正在取得 GPS 定位中...") }
    var isLocating by remember { mutableStateOf(false) }
    val scrollState = rememberScrollState()

    fun triggerLocationFetch() {
        isLocating = true
        resultStatusText = "正在取得 GPS 最新位置..."
        getCurrentLocation(
            context = context,
            onLocationFetched = { lat, lng ->
                isLocating = false
                latVal = lat
                lngVal = lng
                resultStatusText = "定位成功！請選擇科別並點擊搜尋"
                Toast.makeText(context, "定位完成", Toast.LENGTH_SHORT).show()
            },
            onError = { err ->
                isLocating = false
                resultStatusText = "定位失敗：$err (將使用預設位置)"
            }
        )
    }

    val locationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true

        if (granted) {
            triggerLocationFetch()
        } else {
            isLocating = false
            resultStatusText = "未獲得定位權限，請點擊重新定位"
        }
    }

    LaunchedEffect(Unit) {
        val hasFineLocation = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val hasCoarseLocation = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (hasFineLocation || hasCoarseLocation) {
            triggerLocationFetch()
        } else {
            locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
        }
    }

    NavigationSuiteScaffold(
        navigationSuiteItems = {
            AppDestinations.entries.forEach {
                item(
                    icon = {
                        Icon(
                            painter = painterResource(id = it.icon),
                            contentDescription = it.label
                        )
                    },
                    label = { Text(it.label) },
                    selected = it == currentDestination,
                    onClick = { currentDestination = it }
                )
            }
        }
    ) {
        Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
            Column(
                modifier = Modifier
                    .padding(innerPadding)
                    .padding(16.dp)
                    .verticalScroll(scrollState)
            ) {
                Text(
                    text = "🏥 醫療院所搜尋",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold
                )

                Spacer(modifier = Modifier.height(12.dp))

                ExposedDropdownMenuBox(
                    expanded = expanded,
                    onExpandedChange = { expanded = !expanded }
                ) {
                    OutlinedTextField(
                        value = selectedCategory,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("選擇看診科別") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                        modifier = Modifier
                            .menuAnchor()
                            .fillMaxWidth()
                    )

                    ExposedDropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        MEDICAL_CATEGORIES.forEach { category ->
                            DropdownMenuItem(
                                text = { Text(category) },
                                onClick = {
                                    selectedCategory = category
                                    expanded = false
                                }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                Button(
                    onClick = {
                        resultStatusText = "搜尋中..."
                        placesList = emptyList()

                        fetchNearbyMedicalPlaces(
                            userLat = latVal,
                            userLng = lngVal,
                            selectedCategory = selectedCategory,
                            apiKey = myApiKey,
                            onSuccess = { list ->
                                placesList = list
                                if (list.isEmpty()) {
                                    resultStatusText = "附近沒有找到符合【$selectedCategory】的醫療院所"
                                } else {
                                    resultStatusText = "已收錄前 ${list.size} 筆【$selectedCategory】資訊！"
                                }
                            },
                            onError = { error ->
                                resultStatusText = "搜尋失敗：\n$error"
                            }
                        )
                    },
                    enabled = !isLocating,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("搜尋附近【$selectedCategory】")
                }

                Spacer(modifier = Modifier.height(8.dp))

                OutlinedButton(
                    onClick = {
                        val hasFineLocation = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.ACCESS_FINE_LOCATION
                        ) == PackageManager.PERMISSION_GRANTED
                        val hasCoarseLocation = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.ACCESS_COARSE_LOCATION
                        ) == PackageManager.PERMISSION_GRANTED

                        if (hasFineLocation || hasCoarseLocation) {
                            triggerLocationFetch()
                        } else {
                            locationPermissionLauncher.launch(
                                arrayOf(
                                    Manifest.permission.ACCESS_FINE_LOCATION,
                                    Manifest.permission.ACCESS_COARSE_LOCATION
                                )
                            )
                        }
                    },
                    enabled = !isLocating,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = if (isLocating) "⌛ 正在更新定位..." else "🔄 重新取得目前定位")
                }

                Spacer(modifier = Modifier.height(16.dp))

                Text(
                    text = resultStatusText,
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.primary
                )

                Spacer(modifier = Modifier.height(12.dp))

                // 💡 渲染懸浮大按鈕／卡片元件
                placesList.forEach { place ->
                    MedicalPlaceCard(
                        place = place,
                        onNavigateClick = {
                            launchNavigation(
                                context = context,
                                lat = place.lat,
                                lng = place.lng,
                                placeName = place.name
                            )
                        }
                    )
                }
            }
        }
    }
}