export default {
    LiveSelect: {
        syncSelection() {
            const revision = Number(this.el.dataset.selectionRevision)
            const committed = this._selectionUpdates.filter(update => update.revision <= revision)
            const latest = committed[committed.length - 1]
            if (!latest || latest.revision !== revision) {
                return
            }
            this._selectionUpdates = this._selectionUpdates.filter(update => update.revision > revision)
            const { selection, mode } = latest
            let currentText
            let lastInputIndex = -1
            for (const [index, update] of committed.entries()) {
                if (update.current_text != null) {
                    currentText = update.current_text
                }
                if (update.input_event) {
                    lastInputIndex = index
                }
            }
            const inputEvent = lastInputIndex !== -1
            this.selection = selection
            this._skipNextScroll = inputEvent
            if (inputEvent) {
                clearTimeout(this._changeTimeout)
                this._changeTimeout = undefined
                this._pendingText = undefined
            }
            if (currentText != null && this._pendingText === undefined) {
                this.el.querySelector(":scope > div > input[type=text]").value = currentText
            }
            committed.forEach(({ id, parent_event }, index) => {
                if (index === lastInputIndex) {
                    const selector = mode === "single" ? "input.single-mode" :
                        (selection.length === 0 ? "input[data-live-select-empty]" : "input[type=hidden]")
                    this.el.querySelector(selector).dispatchEvent(new Event("input", { bubbles: true }))
                }
                if (parent_event) {
                    const target = this.el.dataset.phxTarget
                    if (target) {
                        this.pushEventTo(target, parent_event, { id })
                    } else {
                        this.pushEvent(parent_event, { id })
                    }
                }
            })
        },
        requestOptions() {
            clearTimeout(this._changeTimeout)
            this._changeTimeout = undefined
            if (this._pendingText === undefined) {
                return
            }
            const text = this._pendingText
            this._pendingText = undefined
            this.pushEventTo(this.el, "change", { text })
            const payload = { id: this.el.id, field: this.el.dataset.field, text }
            const target = this.el.dataset.phxTarget
            if (target) {
                this.pushEventTo(target, "live_select_change", payload)
            } else {
                this.pushEvent("live_select_change", payload)
            }
        },
        mounted() {
            this._selectionUpdates = []
            this._eventHandlers = new AbortController()
            const { signal } = this._eventHandlers

            this.el.addEventListener("keydown", (event) => {
                if (event.target !== this.el.querySelector(":scope > div > input[type=text]") || event.isComposing ||
                    !["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
                    return
                }
                event.preventDefault()
                if (event.key === "Enter") {
                    this.requestOptions()
                } else {
                    this._skipNextScroll = false
                    if (event.key === "Escape") {
                        clearTimeout(this._changeTimeout)
                        this._changeTimeout = undefined
                        this._pendingText = undefined
                    }
                }
                const visualOrder = Array.from(this.el.querySelectorAll(":scope > ul div[data-idx]"))
                    .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)
                    .map(option => parseInt(option.dataset.idx, 10))
                this.pushEventTo(this.el, "keydown", { key: event.key, visual_order: visualOrder })
            }, { signal })

            this.el.addEventListener("input", (event) => {
                if (event.target !== this.el.querySelector(":scope > div > input[type=text]")) {
                    return
                }
                clearTimeout(this._changeTimeout)
                this._changeTimeout = undefined
                const text = event.target.value.trim()
                if (text.length >= parseInt(this.el.dataset.updateMinLen, 10)) {
                    this._pendingText = text
                    this._changeTimeout = setTimeout(() => {
                        this.requestOptions()
                    }, parseInt(this.el.dataset.debounce, 10))
                } else {
                    this._pendingText = undefined
                    this.pushEventTo(this.el, "options_clear", {})
                }
            }, { signal })

            this.el.addEventListener("mousedown", (event) => {
                const dropdown = this.el.querySelector(":scope > ul")
                const option = event.target.closest("div[data-idx]")
                if (option && dropdown && dropdown.contains(option)) {
                    this.pushEventTo(this.el, "option_click", { idx: option.dataset.idx })
                    event.preventDefault()
                }
            }, { signal })

            this.el.addEventListener("focusout", (event) => {
                if (event.target !== this.el.querySelector(":scope > div > input[type=text]")) {
                    return
                }
                clearTimeout(this._changeTimeout)
                this._changeTimeout = undefined
                this._pendingText = undefined
                clearTimeout(this._blurTimeout)
                this._blurTimeout = setTimeout(() => {
                    this._blurTimeout = undefined
                    if (document.activeElement !== this.el.querySelector(":scope > div > input[type=text]")) {
                        this.pushEventTo(this.el, "self_blur", {})
                    }
                }, 100)
            }, { signal })

            this.handleEvent("select", (event) => {
                if (this.el.id !== event.id) {
                    return
                }
                this._selectionUpdates.push(event)
                this.syncSelection()
            })

            this.handleEvent("scroll_to_option", ({ id, idx }) => {
                if (this.el.id !== id) {
                    return
                }
                if (this._skipNextScroll) {
                    this._skipNextScroll = false
                    return
                }
                const option = this.el.querySelector(`:scope > ul div[data-idx="${idx}"]`)
                if (option) {
                    option.scrollIntoView({ block: "nearest", behavior: "instant", container: "nearest" })
                }
            })
        },
        beforeUpdate() {
            const dropdown = this.el.querySelector(":scope > ul")
            this._dropdownScrollTop = dropdown ? dropdown.scrollTop : null
        },
        updated() {
            if (this._dropdownScrollTop != null) {
                const dropdown = this.el.querySelector(":scope > ul")
                if (dropdown) {
                    dropdown.scrollTop = this._dropdownScrollTop
                }
                this._dropdownScrollTop = null
            }
            this.syncSelection()
        },
        disconnected() {
            this._recoverySelection ??= this.selection
            this._selectionUpdates = []
            clearTimeout(this._changeTimeout)
            clearTimeout(this._blurTimeout)
            this._pendingText = undefined
        },
        reconnected() {
            this._selectionUpdates = []
            const recoverySelection = this._recoverySelection ?? this.selection
            if (recoverySelection && recoverySelection.length > 0) {
                this.pushEventTo(this.el, "selection_recovery", recoverySelection).then(results => {
                    if (results.every(result => result.status === "fulfilled") &&
                        this._recoverySelection === recoverySelection) {
                        this._recoverySelection = undefined
                    }
                })
            } else {
                this._recoverySelection = undefined
            }
        },
        destroyed() {
            this._recoverySelection = undefined
            this._selectionUpdates = []
            this._eventHandlers.abort()
            clearTimeout(this._changeTimeout)
            clearTimeout(this._blurTimeout)
            this._pendingText = undefined
        }
    }
}
