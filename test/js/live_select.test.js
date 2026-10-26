import assert from "node:assert/strict"
import { test } from "node:test"
import { JSDOM } from "jsdom"
import { ViewHook } from "../../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js"
import LiveSelect from "../../assets/js/live_select.js"

function mountLiveSelect(t, { mode = "single", selected = false, mount = true } = {}) {
    const dom = new JSDOM(`
        <form id="booking-form">
            <div id="city-select" data-debounce="100" data-update-min-len="2"
                data-field="booking_city" data-selection-revision="0">
                ${mode === "single" || !selected ? "" : `
                    <div class="tags">
                        <div><div><span>London</span></div>
                            <button type="button" data-idx="0" phx-click="option_remove">Remove</button>
                        </div>
                    </div>
                `}
                <div>
                    <input type="text" name="booking[city_text_input]" autocomplete="off">
                    <button type="button" phx-click="clear">Clear</button>
                </div>
                ${mode === "single" ? '<input type="hidden" name="booking[city]" class="single-mode" value="">' :
                    selected ? '<input type="hidden" name="booking[city][]" value="LON">' :
                        '<input type="hidden" name="booking[city][]" value="" data-live-select-empty>'}
                <ul>
                    <li><div data-idx="0"><span>London</span></div></li>
                    <li><div data-idx="1"><span>Lisbon</span></div></li>
                </ul>
            </div>
            <button id="outside" type="button">Continue</button>
        </form>
    `)
    const globals = new Map()
    for (const name of ["document", "Event", "AbortController"]) {
        globals.set(name, Object.getOwnPropertyDescriptor(globalThis, name))
        Object.defineProperty(globalThis, name, { configurable: true, writable: true, value: dom.window[name] })
    }

    const events = []
    const serverEvents = new Map()
    const hook = {
        ...LiveSelect.LiveSelect,
        el: dom.window.document.querySelector("#city-select"),
        handleEvent(name, callback) {
            serverEvents.set(name, callback)
        },
        pushEventTo(target, event, payload) {
            events.push({ target, event, payload })
            return Promise.resolve([{ status: "fulfilled" }])
        },
        pushEvent(event, payload) {
            events.push({ event, payload })
        }
    }
    t.after(() => {
        if (hook._eventHandlers) {
            hook.destroyed()
        }
        dom.window.close()
        for (const [name, descriptor] of globals) {
            if (descriptor) {
                Object.defineProperty(globalThis, name, descriptor)
            } else {
                delete globalThis[name]
            }
        }
    })
    if (mount) {
        hook.mounted()
    }
    return {
        hook,
        events,
        serverEvents,
        window: dom.window,
        document: dom.window.document,
        input: hook.el.querySelector(":scope > div > input[type=text]")
    }
}

test("typing requests options once for the latest trimmed search", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window } = mountLiveSelect(t)
    input.value = "  Lo "
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(99)
    assert.deepEqual(events, [{ target: hook.el, event: "change", payload: { text: "Lo" } }])

    input.value = "  London  "
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(99)
    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "Lo" } },
        { target: hook.el, event: "change", payload: { text: "London" } }
    ])
    t.mock.timers.tick(1)
    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "Lo" } },
        { target: hook.el, event: "change", payload: { text: "London" } },
        { event: "live_select_change", payload: { id: "city-select", field: "booking_city", text: "London" } }
    ])
    t.mock.timers.tick(100)
    assert.equal(events.length, 3)
})

test("search events reach the configured parent component", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window } = mountLiveSelect(t)
    hook.el.dataset.phxTarget = "7"
    input.value = "Lisbon"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(100)

    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "Lisbon" } },
        { target: "7", event: "live_select_change", payload: { id: "city-select", field: "booking_city", text: "Lisbon" } }
    ])
})

test("searching while disconnected handles the native parent push failure", async t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, input, window } = mountLiveSelect(t)
    const pushHookEvent = t.mock.fn(() => Promise.reject(new Error("LiveView not connected")))
    hook.__view = () => ({ pushHookEvent })
    t.mock.method(hook, "pushEvent", ViewHook.prototype.pushEvent)
    hook.disconnected()
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(100)
    await new Promise(resolve => setImmediate(resolve))

    assert.equal(pushHookEvent.mock.callCount(), 1)
    assert.deepEqual(pushHookEvent.mock.calls[0].arguments, [
        hook.el, null, "live_select_change", { id: hook.el.id, field: "booking_city", text: "London" }
    ])
})

test("a parent notification interrupted by disconnect handles the native push failure", async t => {
    const { hook, serverEvents } = mountLiveSelect(t)
    const push = Promise.withResolvers()
    const pushHookEvent = t.mock.fn(() => push.promise)
    hook.__view = () => ({ pushHookEvent })
    t.mock.method(hook, "pushEvent", ViewHook.prototype.pushEvent)
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [], parent_event: "city_focused"
    })
    hook.disconnected()
    push.reject(new Error("LiveView not connected"))
    await new Promise(resolve => setImmediate(resolve))

    assert.equal(pushHookEvent.mock.callCount(), 1)
})

test("shortening the search clears options and cancels the pending request", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window } = mountLiveSelect(t)
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    input.value = " L "
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(200)

    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "London" } },
        { target: hook.el, event: "options_clear", payload: {} }
    ])
})

test("Enter sends a pending search before selecting and does not send it again", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window } = mountLiveSelect(t)
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    const enter = new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
    input.dispatchEvent(enter)

    assert.equal(enter.defaultPrevented, true)
    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "London" } },
        { event: "live_select_change", payload: { id: "city-select", field: "booking_city", text: "London" } },
        { target: hook.el, event: "keydown", payload: { key: "Enter", visual_order: [0, 1] } }
    ])
    t.mock.timers.tick(200)
    assert.equal(events.length, 3)
})

test("typing after Enter cancels its pending selection before the next search debounce", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window } = mountLiveSelect(t)
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    input.value = "Lisbon"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))

    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "London" } },
        { event: "live_select_change", payload: { id: hook.el.id, field: "booking_city", text: "London" } },
        { target: hook.el, event: "keydown", payload: { key: "Enter", visual_order: [0, 1] } },
        { target: hook.el, event: "change", payload: { text: "Lisbon" } }
    ])
    t.mock.timers.tick(100)
    assert.deepEqual(events[4], {
        event: "live_select_change", payload: { id: hook.el.id, field: "booking_city", text: "Lisbon" }
    })
    assert.equal(events.length, 5)
})

test("Escape cancels a pending search", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window } = mountLiveSelect(t)
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    t.mock.timers.tick(200)

    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "London" } },
        { target: hook.el, event: "keydown", payload: { key: "Escape", visual_order: [0, 1] } }
    ])
})

test("ordinary typing and composition keys retain their native behavior", t => {
    const { events, input, window } = mountLiveSelect(t)
    for (const options of [{ key: "a" }, { key: "Tab" }, { key: "Enter", isComposing: true }]) {
        const event = new window.KeyboardEvent("keydown", { ...options, bubbles: true, cancelable: true })
        input.dispatchEvent(event)
        assert.equal(event.defaultPrevented, false)
    }
    assert.deepEqual(events, [])
})

test("navigation uses the dropdown's displayed option order", t => {
    const { hook, events, input, window } = mountLiveSelect(t, { mode: "tags", selected: true })
    const tag = hook.el.querySelector(".tags span")
    tag.dataset.idx = "99"
    const options = hook.el.querySelectorAll(":scope > ul div[data-idx]")
    t.mock.method(options[0], "getBoundingClientRect", () => ({ top: 40 }))
    t.mock.method(options[1], "getBoundingClientRect", () => ({ top: 20 }))
    const arrow = new window.KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true })
    input.dispatchEvent(arrow)

    assert.equal(arrow.defaultPrevented, true)
    assert.deepEqual(events, [
        { target: hook.el, event: "keydown", payload: { key: "ArrowDown", visual_order: [1, 0] } }
    ])
})

test("custom tag controls do not trigger search, navigation, or option selection", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, window } = mountLiveSelect(t, { mode: "tags", selected: true })
    const slot = hook.el.querySelector(".tags span")
    slot.innerHTML = '<input type="text" value="London"><div data-idx="99"><span>Details</span></div>'
    const customInput = slot.querySelector("input")
    customInput.dispatchEvent(new window.Event("input", { bubbles: true }))
    customInput.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    customInput.dispatchEvent(new window.FocusEvent("focusout", { bubbles: true }))
    const click = new window.MouseEvent("mousedown", { bubbles: true, cancelable: true })
    slot.querySelector("div span").dispatchEvent(click)
    t.mock.timers.tick(200)

    assert.equal(click.defaultPrevented, false)
    assert.deepEqual(events, [])
})

test("clicking nested option content selects it without moving focus", t => {
    const { hook, events, input, window, document } = mountLiveSelect(t)
    input.focus()
    const click = new window.MouseEvent("mousedown", { bubbles: true, cancelable: true })
    hook.el.querySelector('ul div[data-idx="1"] span').dispatchEvent(click)

    assert.equal(click.defaultPrevented, true)
    assert.equal(document.activeElement, input)
    assert.deepEqual(events, [{ target: hook.el, event: "option_click", payload: { idx: "1" } }])
})

test("delegated listeners survive input and dropdown replacement without duplicating events", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window } = mountLiveSelect(t)
    const replacement = input.cloneNode()
    const dropdown = hook.el.querySelector(":scope > ul")
    const replacementDropdown = dropdown.cloneNode(true)
    hook.beforeUpdate()
    input.replaceWith(replacement)
    dropdown.replaceWith(replacementDropdown)
    hook.updated()
    hook.updated()
    replacement.value = "London"
    replacement.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(100)
    replacementDropdown.querySelector("span").dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true }))

    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "London" } },
        { event: "live_select_change", payload: { id: "city-select", field: "booking_city", text: "London" } },
        { target: hook.el, event: "option_click", payload: { idx: "0" } }
    ])
})

test("hook listeners coexist with the application's native event handlers", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, input, window } = mountLiveSelect(t, { mount: false })
    const applicationInput = t.mock.fn()
    const applicationKeydown = t.mock.fn()
    input.oninput = applicationInput
    input.onkeydown = applicationKeydown
    hook.mounted()
    hook.updated()
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))

    assert.equal(applicationInput.mock.callCount(), 1)
    assert.equal(applicationKeydown.mock.callCount(), 1)
})

test("a selection event waits for its matching form patch before notifying the parent", t => {
    const { hook, serverEvents, document, input } = mountLiveSelect(t)
    const submitted = []
    document.querySelector("form").addEventListener("input", event => {
        submitted.push({ name: event.target.name, value: event.target.value, text: input.value })
    })
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "London", value: "LON" }],
        current_text: "London", input_event: true
    })
    assert.deepEqual(submitted, [])

    hook.el.querySelector("input.single-mode").value = "LON"
    hook.el.dataset.selectionRevision = "1"
    hook.updated()

    assert.deepEqual(submitted, [{ name: "booking[city]", value: "LON", text: "London" }])
    hook.updated()
    assert.equal(submitted.length, 1)
})

test("a selection event arriving after its patch notifies the form immediately", t => {
    const { hook, serverEvents, document } = mountLiveSelect(t)
    const submitted = []
    document.querySelector("form").addEventListener("input", event => submitted.push(event.target.value))
    hook.el.dataset.selectionRevision = "1"
    hook.el.querySelector("input.single-mode").value = "LIS"
    hook.updated()
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "Lisbon", value: "LIS" }], input_event: true
    })

    assert.deepEqual(submitted, ["LIS"])
})

test("coalesced patches notify the form once with the latest value and preserve parent event order", t => {
    const { hook, serverEvents, events, document, input } = mountLiveSelect(t)
    const notifications = []
    document.querySelector("form").addEventListener("input", event => notifications.push(event.target.value))
    t.mock.method(hook, "pushEvent", (event, payload) => notifications.push({ event, payload }))
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "London", value: "LON" }],
        current_text: "London", input_event: true, parent_event: "city_blurred"
    })
    serverEvents.get("select")({
        id: hook.el.id, revision: 2, mode: "single", selection: [{ label: "Lisbon", value: "LIS" }],
        current_text: "Lisbon", input_event: true, parent_event: "city_changed"
    })
    serverEvents.get("select")({
        id: hook.el.id, revision: 3, mode: "single", selection: [{ label: "Lisbon", value: "LIS" }],
        parent_event: "city_focused"
    })
    hook.el.dataset.selectionRevision = "3"
    hook.el.querySelector("input.single-mode").value = "LIS"
    hook.updated()

    assert.deepEqual(notifications, [
        { event: "city_blurred", payload: { id: hook.el.id } },
        "LIS",
        { event: "city_changed", payload: { id: hook.el.id } },
        { event: "city_focused", payload: { id: hook.el.id } }
    ])
    assert.equal(input.value, "Lisbon")
    assert.deepEqual(events, [])
})

test("selection parent events reach the configured component after its patch", t => {
    const { hook, serverEvents, events } = mountLiveSelect(t)
    hook.el.dataset.phxTarget = "7"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [], parent_event: "city_focused"
    })
    assert.deepEqual(events, [])
    hook.el.dataset.selectionRevision = "1"
    hook.updated()

    assert.deepEqual(events, [{ target: "7", event: "city_focused", payload: { id: hook.el.id } }])
})

test("another LiveSelect's events do not change this field or scroll its options", t => {
    const { hook, serverEvents, input } = mountLiveSelect(t)
    const scroll = t.mock.fn()
    hook.el.querySelector("ul div").scrollIntoView = scroll
    hook.el.dataset.selectionRevision = "1"
    input.value = "London"
    serverEvents.get("select")({ id: "other-select", revision: 1, mode: "single", selection: [], current_text: "" })
    serverEvents.get("scroll_to_option")({ id: "other-select", idx: 0 })

    assert.equal(input.value, "London")
    assert.equal(scroll.mock.callCount(), 0)
})

test("focus patches preserve a search typed while waiting for the server", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, serverEvents, input, window, events } = mountLiveSelect(t)
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [], current_text: "", input_event: false
    })
    assert.equal(input.value, "London")
    t.mock.timers.tick(100)
    assert.equal(events.find(event => event.event === "change").payload.text, "London")
})

test("a delayed focus reply preserves the search after its debounce has fired", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, serverEvents, input, window, events } = mountLiveSelect(t)
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(100)
    assert.equal(events.find(event => event.event === "change").payload.text, "London")

    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [], current_text: "", input_event: false
    })

    assert.equal(input.value, "London")
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    assert.deepEqual(events.map(event => event.event), ["change", "live_select_change", "keydown"])
})

test("a delayed focus reply preserves a short query while its options are cleared", t => {
    const { hook, serverEvents, input, window, events } = mountLiveSelect(t)
    input.value = "L"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [], current_text: "", input_event: false
    })

    assert.equal(input.value, "L")
    assert.deepEqual(events, [{ target: hook.el, event: "options_clear", payload: {} }])
})

test("Escape ends a sent search so its response can restore the selected label", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, serverEvents, input, window } = mountLiveSelect(t)
    input.value = "Lisbon"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(100)
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "London", value: "LON" }],
        current_text: "London"
    })

    assert.equal(input.value, "London")
})

test("leaving a sent search lets the blur response restore the selected label", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, serverEvents, input, window, document } = mountLiveSelect(t)
    input.focus()
    input.value = "Lisbon"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    t.mock.timers.tick(100)
    document.querySelector("#outside").focus()
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "London", value: "LON" }],
        current_text: "London"
    })

    assert.equal(input.value, "London")
})

test("committing a selection cancels an older pending search", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, serverEvents, input, window, events } = mountLiveSelect(t)
    input.value = "Lis"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    hook.el.dataset.selectionRevision = "1"
    hook.el.querySelector("input.single-mode").value = "LIS"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "Lisbon", value: "LIS" }],
        current_text: "Lisbon", input_event: true
    })
    t.mock.timers.tick(200)

    assert.equal(input.value, "Lisbon")
    assert.deepEqual(events, [{ target: hook.el, event: "change", payload: { text: "Lis" } }])
})

for (const mode of ["tags", "quick_tags"]) {
    test(`${mode} selection notifies the form through its selected value`, t => {
        const { hook, serverEvents, document, window } = mountLiveSelect(t, { mode, selected: true })
        const submitted = []
        document.querySelector("form").addEventListener("input", event => {
            submitted.push({ name: event.target.name, value: event.target.value })
        })
        hook.el.dataset.selectionRevision = "1"
        serverEvents.get("select")({
            id: hook.el.id, revision: 1, mode, selection: [{ label: "London", value: "LON" }], input_event: true
        })

        assert.deepEqual(submitted, [{ name: "booking[city][]", value: "LON" }])
        assert.deepEqual(new window.FormData(document.querySelector("form")).getAll("booking[city][]"), ["LON"])
    })

    test(`clearing ${mode} submits an empty value under the native multiple field name`, t => {
        const { hook, serverEvents, document, window } = mountLiveSelect(t, { mode })
        const submitted = []
        document.querySelector("form").addEventListener("input", event => {
            submitted.push({ name: event.target.name, value: event.target.value })
        })
        hook.el.dataset.selectionRevision = "1"
        serverEvents.get("select")({ id: hook.el.id, revision: 1, mode, selection: [], input_event: true })

        assert.deepEqual(submitted, [{ name: "booking[city][]", value: "" }])
        assert.deepEqual(new window.FormData(document.querySelector("form")).getAll("booking[city][]"), [""])
    })
}

test("custom tag fields do not receive the selection's form event", t => {
    const { hook, serverEvents, document } = mountLiveSelect(t, { mode: "tags", selected: true })
    hook.el.querySelector(".tags span").innerHTML = '<input type="hidden" name="tag_details" value="extra">'
    const submitted = []
    document.querySelector("form").addEventListener("input", event => submitted.push(event.target.name))
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "tags", selection: [{ label: "London", value: "LON" }], input_event: true
    })

    assert.deepEqual(submitted, ["booking[city][]"])
})

test("leaving the search cancels its request and hides options after the focus delay", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window, document } = mountLiveSelect(t)
    input.focus()
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    document.querySelector("#outside").focus()
    t.mock.timers.tick(99)
    assert.deepEqual(events, [{ target: hook.el, event: "change", payload: { text: "London" } }])
    t.mock.timers.tick(1)

    assert.deepEqual(events, [
        { target: hook.el, event: "change", payload: { text: "London" } },
        { target: hook.el, event: "self_blur", payload: {} }
    ])
})

test("returning to the search before the focus delay keeps options open", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { events, input, document } = mountLiveSelect(t)
    input.focus()
    document.querySelector("#outside").focus()
    t.mock.timers.tick(50)
    input.focus()
    t.mock.timers.tick(100)

    assert.deepEqual(events, [])
})

test("a patched dropdown keeps its scroll position", t => {
    const { hook } = mountLiveSelect(t)
    const dropdown = hook.el.querySelector(":scope > ul")
    dropdown.scrollTop = 120
    hook.beforeUpdate()
    const replacement = dropdown.cloneNode(true)
    dropdown.replaceWith(replacement)
    hook.updated()

    assert.equal(replacement.scrollTop, 120)
    replacement.scrollTop = 60
    hook.updated()
    assert.equal(replacement.scrollTop, 60)
})

test("selection skips the resulting scroll request while keyboard navigation resumes scrolling", t => {
    const { hook, serverEvents, input, window } = mountLiveSelect(t)
    const option = hook.el.querySelector('ul div[data-idx="1"]')
    const scroll = t.mock.fn()
    option.scrollIntoView = scroll
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "London", value: "LON" }], input_event: true
    })
    serverEvents.get("scroll_to_option")({ id: hook.el.id, idx: 1 })
    assert.equal(scroll.mock.callCount(), 0)
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))
    serverEvents.get("scroll_to_option")({ id: hook.el.id, idx: 1 })

    assert.equal(scroll.mock.callCount(), 1)
    assert.deepEqual(scroll.mock.calls[0].arguments, [{ block: "nearest", behavior: "instant", container: "nearest" }])
})

test("disconnect cancels pending searches and delayed blur events", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window, document } = mountLiveSelect(t)
    input.focus()
    document.querySelector("#outside").focus()
    input.focus()
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    hook.disconnected()
    t.mock.timers.tick(200)

    assert.deepEqual(events, [{ target: hook.el, event: "change", payload: { text: "London" } }])
})

test("reconnect retries the cached selection until recovery succeeds", async t => {
    const { hook, serverEvents, events } = mountLiveSelect(t)
    const london = [{ label: "London", value: "LON", tag_label: "London, UK" }]
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({ id: hook.el.id, revision: 1, mode: "single", selection: london })
    hook.disconnected()
    t.mock.method(hook, "pushEventTo", (target, event, payload) => {
        events.push({ target, event, payload })
        return Promise.resolve([{ status: events.length === 1 ? "rejected" : "fulfilled" }])
    })
    hook.reconnected()
    await Promise.resolve()

    hook.el.dataset.selectionRevision = "2"
    serverEvents.get("select")({
        id: hook.el.id, revision: 2, mode: "single", selection: [{ label: "LON", value: "LON" }]
    })
    hook.disconnected()
    hook.reconnected()
    await Promise.resolve()
    assert.deepEqual(events, [
        { target: hook.el, event: "selection_recovery", payload: london },
        { target: hook.el, event: "selection_recovery", payload: london }
    ])

    hook.el.dataset.selectionRevision = "3"
    serverEvents.get("select")({
        id: hook.el.id, revision: 3, mode: "single", selection: [{ label: "Lisbon", value: "LIS" }]
    })
    hook.disconnected()
    hook.reconnected()
    await Promise.resolve()
    assert.deepEqual(events[2], {
        target: hook.el, event: "selection_recovery", payload: [{ label: "Lisbon", value: "LIS" }]
    })
})

test("an empty selection does not request recovery", t => {
    const { hook, events, serverEvents } = mountLiveSelect(t)
    hook.el.dataset.selectionRevision = "1"
    serverEvents.get("select")({ id: hook.el.id, revision: 1, mode: "single", selection: [] })
    hook.disconnected()
    hook.reconnected()

    assert.deepEqual(events, [])
})

test("disconnect discards selection notifications awaiting an older DOM patch", t => {
    const { hook, serverEvents, document } = mountLiveSelect(t)
    const submitted = []
    document.querySelector("form").addEventListener("input", event => submitted.push(event.target.value))
    serverEvents.get("select")({
        id: hook.el.id, revision: 1, mode: "single", selection: [{ label: "London", value: "LON" }], input_event: true
    })
    hook.disconnected()
    hook.reconnected()
    hook.el.dataset.selectionRevision = "1"
    hook.updated()

    assert.deepEqual(submitted, [])
})

test("destroy removes DOM listeners and cancels all pending work", t => {
    t.mock.timers.enable({ apis: ["setTimeout"] })
    const { hook, events, input, window, document } = mountLiveSelect(t)
    const applicationInput = t.mock.fn()
    input.oninput = applicationInput
    input.focus()
    document.querySelector("#outside").focus()
    input.focus()
    input.value = "London"
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    hook.destroyed()
    input.dispatchEvent(new window.Event("input", { bubbles: true }))
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    hook.el.querySelector("ul span").dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true }))
    t.mock.timers.tick(200)

    assert.deepEqual(events, [{ target: hook.el, event: "change", payload: { text: "London" } }])
    assert.equal(applicationInput.mock.callCount(), 2)
})
