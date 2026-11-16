package io.github.ccch1mneyyy.dsh_app.nativeanimation

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import org.json.JSONObject
import java.io.File
import kotlin.math.floor

internal fun Map<*, *>.number(key: String, default: Double = 0.0) = (this[key] as? Number)?.toDouble() ?: default
internal fun Map<*, *>.flag(key: String, default: Boolean = false) = this[key] as? Boolean ?: default
internal fun Map<*, *>.rect(key: String): RectF {
    val r = this[key] as List<*>
    require(r.size == 4)
    val a = r.map { (it as Number).toFloat() }
    return RectF(a[0], a[1], a[0] + a[2], a[1] + a[3])
}
internal fun Map<*, *>.point(key: String): MotionPoint {
    val values = this[key] as List<*>
    require(values.size == 2)
    return MotionPoint((values[0] as Number).toFloat(), (values[1] as Number).toFloat())
}

/** All scene state and decoded images belong to the renderer thread. */
internal sealed class AnimationScene {
    abstract fun configure(config: Map<*, *>)
    abstract fun draw(canvas: Canvas, elapsed: Long, alpha: Float)
    /** null means no more frames; a non-looping animation may still have an end callback due. */
    abstract fun nextDelay(elapsed: Long): Long?
    open fun ended(elapsed: Long) = false
    open fun close() {}
}

internal class SpriteScene(private val context: Context) : AnimationScene() {
    private var source = ""
    private var bitmap: Bitmap? = null
    private var sequence: SpriteSequence? = null
    private var columns = 1
    private var cellWidth = 1
    private var cellHeight = 1
    private var still = false
    private var endWhenStill = true
    private var flip = false
    private var filtered = false
    private var anchorX = 0f
    private val target = RectF()
    private val sourceRect = Rect()
    private val paint = Paint()
    private var playback: List<Any?>? = null
    /** true only when the frame clock needs to restart, never on a geometry update. */
    var restarted = false
        private set

    override fun configure(config: Map<*, *>) {
        val asset = config["asset"] as? String
        val path = config["path"] as? String
        require((asset != null) != (path != null)) { "One sprite source is required" }
        val key = asset ?: path!!
        if (key != source) {
            val decoded = if (asset != null) {
                require(!asset.startsWith('/') && !asset.split('/').contains("..")) { "Invalid sprite asset" }
                val lookup = if (asset.startsWith("flutter_assets/")) asset else "flutter_assets/$asset"
                context.assets.open(lookup).use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inScaled = false }) }
            } else {
                val file = File(path!!).canonicalFile
                val roots = listOf(context.filesDir, context.cacheDir).map { it.canonicalFile }
                require(roots.any { file.toPath().startsWith(it.toPath()) }) { "Sprite must be in app storage" }
                BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inScaled = false })
            } ?: error("Sprite image could not be decoded")
            bitmap?.recycle()
            bitmap = decoded
            source = key
        }
        val cells = (config["frames"] as List<*>).map { it as Map<*, *> }
        val loop = config.flag("loop", true)
        val nextPlayback = listOf(key, cells, loop, config["playbackSerial"], config.flag("still"), config.flag("endWhenStill", true))
        restarted = nextPlayback != playback
        if (restarted) {
            sequence = SpriteSequence(cells.map { it.number("i").toInt() }, cells.map { it.number("ms").toLong() }, loop)
            playback = nextPlayback
        }
        columns = config.number("columns").toInt()
        cellWidth = config.number("cellWidth").toInt()
        cellHeight = config.number("cellHeight").toInt()
        require(columns > 0 && cellWidth > 0 && cellHeight > 0)
        val b = bitmap!!
        require(columns.toLong() * cellWidth <= b.width && cells.all { c ->
            val i = c.number("i").toLong()
            i >= 0 && (i / columns + 1) * cellHeight <= b.height
        }) { "Sprite frame outside image" }
        target.set(config.rect("dst"))
        still = config.flag("still")
        endWhenStill = config.flag("endWhenStill", true)
        flip = config.flag("flip")
        filtered = config["filter"] == "linear"
        anchorX = config.number("anchorX", target.centerX().toDouble()).toFloat()
    }

    override fun draw(canvas: Canvas, elapsed: Long, alpha: Float) {
        val frames = sequence ?: return
        val b = bitmap ?: return
        val cell = frames.cells[if (still) 0 else frames.frame(elapsed)]
        sourceRect.set((cell % columns) * cellWidth, (cell / columns) * cellHeight, (cell % columns + 1) * cellWidth, (cell / columns + 1) * cellHeight)
        paint.isFilterBitmap = filtered
        paint.alpha = (alpha * 255).toInt().coerceIn(0, 255)
        canvas.save()
        if (flip) canvas.scale(-1f, 1f, anchorX, target.centerY())
        canvas.drawBitmap(b, sourceRect, target, paint)
        canvas.restore()
    }

    override fun nextDelay(elapsed: Long): Long? {
        val frames = sequence ?: return null
        if (frames.ended(elapsed)) return null
        if (still) return if (frames.loop || !endWhenStill) null else frames.duration - elapsed
        return frames.nextVisualDelay(elapsed)
    }
    override fun ended(elapsed: Long) = (!still || endWhenStill) && sequence?.ended(elapsed) == true
    override fun close() { bitmap?.recycle(); bitmap = null }
}

internal class DotScene : AnimationScene() {
    private var color = Color.BLACK
    private var pulse = true
    private var period = 2400L
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    override fun configure(config: Map<*, *>) {
        color = config.number("color").toLong().toInt()
        pulse = config.flag("pulse", true)
        period = config.number("periodMs", 2400.0).toLong()
        require(period > 0)
    }
    override fun draw(canvas: Canvas, elapsed: Long, alpha: Float) {
        val half = period / 2.0
        val p = elapsed % period
        val t = if (p <= half) p / half else (period - p) / half
        val opacity = if (pulse) 1 - .65 * cubicEase(t) else 1.0
        paint.color = color
        paint.alpha = (Color.alpha(color) * opacity * alpha).toInt().coerceIn(0, 255)
        val radius = minOf(canvas.width, canvas.height) / 2f
        canvas.drawCircle(canvas.width / 2f, canvas.height / 2f, radius, paint)
    }
    override fun nextDelay(elapsed: Long): Long? = if (pulse) continuousDelay(elapsed) else null
}

/** Same fractional-frame interpolation and level cross-fade as WhaleTail's Dart painter. */
internal class WhaleScene(context: Context) : AnimationScene() {
    private data class Sheet(val image: Bitmap, val frames: Int, val frameMs: Int)
    private val sheets: Map<Int, Sheet>
    private val width: Int
    private val height: Int
    private val columns: Int
    private val src = Rect()
    private val dst = RectF()
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val add = PorterDuffXfermode(PorterDuff.Mode.ADD)
    private val phases = mutableMapOf<Int, Double>()
    private var form = 2
    private var previous: Int? = null
    private var mix = 1.0
    private var rate = .5
    private var level = 1
    private var color = Color.BLACK
    private var last = 0L
    private var configured = false

    init {
        val root = "flutter_assets/assets/whale/"
        val manifest = context.assets.open(root + "whale.json").bufferedReader().use { JSONObject(it.readText()) }
        width = manifest.getInt("frameWidth")
        height = manifest.getInt("frameHeight")
        columns = manifest.getInt("columns")
        val levels = manifest.getJSONArray("levels")
        val loaded = mutableMapOf<Int, Sheet>()
        try {
            for (i in 0 until levels.length()) {
                val s = levels.getJSONObject(i)
                val bitmap = context.assets.open(root + s.getString("image")).use {
                    BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inScaled = false })
                } ?: error("Whale image could not be decoded")
                loaded[s.getInt("level")] = Sheet(bitmap, s.getInt("frames"), s.getInt("frameMs"))
            }
            sheets = loaded
        } catch (e: Exception) {
            loaded.values.forEach { it.image.recycle() }
            throw e
        }
    }
    override fun configure(config: Map<*, *>) {
        level = config.number("level", 1.0).toInt()
        color = config.number("color").toLong().toInt()
        val next = whaleForm(level)
        if (!configured) { form = next; rate = whaleRate(level); configured = true }
        else if (next != form) { previous = form; form = next; mix = 0.0 }
    }
    override fun draw(canvas: Canvas, elapsed: Long, alpha: Float) {
        val seconds = (elapsed - last).coerceAtLeast(0) / 1000.0
        last = elapsed
        rate = approachWhaleRate(rate, whaleRate(level), seconds)
        listOfNotNull(form, previous).forEach { f ->
            val sheet = sheets.getValue(f)
            if (sheet.frameMs > 0) phases[f] = ((phases[f] ?: 0.0) + seconds * 1000 / sheet.frameMs * rate) % sheet.frames
        }
        previous?.let { old ->
            mix = (mix + seconds / .32).coerceAtMost(1.0)
            if (mix == 1.0) { phases.remove(old); previous = null }
        }
        dst.set(0f, 0f, canvas.width.toFloat(), canvas.height.toFloat())
        val saved = canvas.saveLayer(dst, null)
        var first = true
        fun drawFrame(f: Int, cell: Int, weight: Double) {
            if (weight <= 0) return
            val sheet = sheets.getValue(f)
            src.set(cell % columns * width, cell / columns * height, (cell % columns + 1) * width, (cell / columns + 1) * height)
            val tint = (color and 0x00ffffff) or ((Color.alpha(color) * weight * alpha).toInt().coerceIn(0, 255) shl 24)
            paint.colorFilter = PorterDuffColorFilter(tint, PorterDuff.Mode.SRC_IN)
            paint.xfermode = if (first) null else add
            canvas.drawBitmap(sheet.image, src, dst, paint)
            first = false
        }
        fun drawForm(f: Int, weight: Double) {
            val sheet = sheets.getValue(f)
            val phase = phases[f] ?: 0.0
            val a = floor(phase).toInt() % sheet.frames
            val t = phase - floor(phase)
            drawFrame(f, a, weight * (1 - t))
            if (t > 0) drawFrame(f, (a + 1) % sheet.frames, weight * t)
        }
        previous?.let { drawForm(it, 1 - mix) }
        drawForm(form, if (previous == null) 1.0 else mix)
        canvas.restoreToCount(saved)
    }
    override fun nextDelay(elapsed: Long): Long = continuousDelay(elapsed)
    override fun close() = sheets.values.forEach { it.image.recycle() }
}

internal fun continuousDelay(elapsed: Long): Long = (kotlin.math.ceil((elapsed * 60 / 1000 + 1) * 1000.0 / 60).toLong() - elapsed).coerceAtLeast(1)
