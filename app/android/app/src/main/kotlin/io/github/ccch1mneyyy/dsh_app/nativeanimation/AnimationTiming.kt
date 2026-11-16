package io.github.ccch1mneyyy.dsh_app.nativeanimation

import kotlin.math.exp

/** Source durations, independent of the time spent locking and posting a Surface buffer. */
internal class SpriteSequence(val cells: List<Int>, durations: List<Long>, val loop: Boolean) {
    init {
        require(cells.isNotEmpty() && cells.size == durations.size)
        require(cells.all { it >= 0 } && durations.all { it > 0 })
    }
    private val ends = durations.runningFold(0L) { sum, duration -> Math.addExact(sum, duration) }.drop(1)
    val duration = ends.last()
    fun ended(elapsed: Long) = !loop && elapsed >= duration
    fun frame(elapsed: Long): Int {
        val position = if (loop) elapsed.coerceAtLeast(0) % duration else elapsed.coerceIn(0, duration - 1)
        val found = ends.binarySearch(position + 1)
        return if (found >= 0) found else -found - 1
    }
    fun nextVisualDelay(elapsed: Long): Long? {
        if (ended(elapsed)) return null
        val current = frame(elapsed)
        var index = current
        var delay = remaining(elapsed)
        while (true) {
            index++
            if (index == cells.size) {
                if (!loop) return duration - elapsed
                index = 0
            }
            if (cells[index] != cells[current]) return delay
            if (index == current) return null
            delay += ends[index] - (if (index == 0) 0L else ends[index - 1])
        }
    }
    fun remaining(elapsed: Long): Long {
        if (ended(elapsed)) return Long.MAX_VALUE
        val position = if (loop) elapsed.coerceAtLeast(0) % duration else elapsed.coerceAtLeast(0)
        return ends[frame(elapsed)] - position
    }
}

internal data class MotionPoint(val x: Float, val y: Float)
internal class SpriteMotion(
    val serial: Any?, val kind: String, val duration: Long,
    private val from: MotionPoint, private val to: MotionPoint, private val height: Float,
) {
    init { require(duration >= 0 && kind in setOf("hop", "walk", "drop")) }
    fun point(elapsed: Long): MotionPoint {
        val t = if (duration == 0L) 1.0 else (elapsed.toDouble() / duration).coerceIn(0.0, 1.0)
        val eased = when (kind) {
            "hop" -> cubicEase(t, 0.42, 0.0, 0.58, 1.0)
            "drop" -> cubicEase(t, 0.42, 0.0, 1.0, 1.0)
            else -> t
        }
        val lift = if (kind == "hop") 4 * height * t * (1 - t) else 0.0
        return MotionPoint((from.x + (to.x - from.x) * eased).toFloat(), (from.y + (to.y - from.y) * eased - lift).toFloat())
    }
}

/** Flutter Easing.standard and the motion curves use cubic Bézier x inversion. */
internal fun cubicEase(t: Double, x1: Double = .2, y1: Double = 0.0, x2: Double = 0.0, y2: Double = 1.0): Double {
    if (t <= 0 || t >= 1) return t.coerceIn(0.0, 1.0)
    fun bezier(u: Double, a: Double, b: Double): Double {
        val v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }
    var lo = 0.0
    var hi = 1.0
    repeat(20) { val mid = (lo + hi) / 2; if (bezier(mid, x1, x2) < t) lo = mid else hi = mid }
    return bezier((lo + hi) / 2, y1, y2)
}

internal fun whaleForm(level: Int) = if (level <= 2) 2 else level.coerceIn(2, 4)
internal fun whaleRate(level: Int) = when { level <= 0 -> .3; level == 1 -> .5; else -> 1.0 }
internal fun approachWhaleRate(rate: Double, target: Double, seconds: Double) = rate + (target - rate) * (1 - exp(-seconds / .35))
