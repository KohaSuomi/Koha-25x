<template>
    <div v-if="!initialized">{{ $__("Loading") }}</div>
    <div v-else id="hold_pickup_shelves_list">
        <Toolbar>
            <ToolbarButton
                :to="{ name: 'HoldPickupShelvesFormAdd' }"
                icon="plus"
                :title="$__('New pickup shelf')"
            />
        </Toolbar>
        <h1>{{ title }}</h1>
        <div v-if="hold_pickup_shelves_any > 0" class="page-section">
            <div class="mb-3">
                <label for="libraryFilter" class="pe-1">{{ $__("Filter by library") }}:</label>
                <select id="libraryFilter" v-model="library_id" @change="fetchLibraryHoldPickupShelves($event)">
                    <option :value="null">{{ $__("All libraries") }}</option>
                    <option v-for="library in libraries" :key="library.library_id" :value="library.library_id">
                        {{ library.name }}
                    </option>
                </select>
            </div>
            <KohaTable
                ref="table"
                v-bind="tableOptions"
                @edit="doEdit"
                @editTab="doEditTab"
                @delete="doDelete"
            ></KohaTable>
        </div>
        <div v-else class="alert alert-info">
            {{ $__("There are no hold pickup shelves defined") }}
        </div>
    </div>
</template>

<script>
import Toolbar from "../../Toolbar.vue";
import ToolbarButton from "../../ToolbarButton.vue";
import { inject } from "vue";
import { APIClient } from "../../../fetch/api-client.js";
import KohaTable from "../../KohaTable.vue";

export default {
    props: {
        libraries: Array,
        categories: Array,
        biblio_level_itemtypes: Array,
    },
    data() {
        return {
            title: this.$__("Hold pickup shelves"),
            tableOptions: {
                columns: [
                    {
                        title: this.$__("ID"),
                        data: "hold_pickup_shelf_id",
                        searchable: true,
                    },
                    {
                        title: this.$__("Priority"),
                        data: "priority",
                        searchable: true,
                        orderable: true,
                        render: (data, type, row) => {
                            return `
                                <div style="display:flex;align-items:center;gap:2px;">
                                    <button type="button" class="priority-arrow-last" data-id="${row.hold_pickup_shelf_id}" data-priority="${data}" title="${this.$__('Set last priority')}" style="border:none;background:none;padding:0 2px;font-size:16px;">&#8659;</button>
                                    <button type="button" class="priority-arrow-down" data-id="${row.hold_pickup_shelf_id}" data-priority="${data}" title="${this.$__('Decrease priority')}" style="border:none;background:none;padding:0 2px;font-size:16px;">&#8595;</button>
                                    <span style="min-width:30px;display:inline-block;text-align:center;">${data !== null ? data : ''}</span>
                                    <button type="button" class="priority-arrow-up" data-id="${row.hold_pickup_shelf_id}" data-priority="${data}" title="${this.$__('Increase priority')}" style="border:none;background:none;padding:0 2px;font-size:16px;">&#8593;</button>
                                    <button type="button" class="priority-arrow-first" data-id="${row.hold_pickup_shelf_id}" data-priority="${data}" title="${this.$__('Set first priority')}" style="border:none;background:none;padding:0 2px;font-size:16px;">&#8657;</button>
                                </div>
                            `;
                        },
                    },
                    {
                        title: this.$__("Library name"),
                        data: "library.name",
                        searchable: true,
                    },
                    {
                        title: this.$__("Shelf name"),
                        data: "shelf_name",
                        searchable: true,
                    },
                    {
                        title: this.$__("Items / Max items"),
                        data: "max_items",
                        searchable: true,
                        orderable: true,
                        render: (data, type, row) => {
                            const holds_count = row.holds_count !== null ? row.holds_count : 0;
                            const max_items = data;
                            return `${holds_count} / ${max_items}`;
                        },
                    },
                    {
                        title: this.$__("Weekday"),
                        data: "weekday",
                        searchable: true,
                        orderable: true,
                        render: data => {
                            return data
                                ? this.$__("%s").format(data)
                                : this.$__("Any");
                        },
                    },
                    {
                        title: this.$__("Patron category"),
                        data: "patron_category.name",
                        searchable: true,
                        orderable: true,
                        render: data => {
                            return data
                                ? data
                                : this.$__("Any");
                        },
                    },
                    {
                        title: this.$__("Biblio level itemtype"),
                        data: "biblio_itemtype",
                        searchable: true,
                        orderable: true,
                        render: data => {
                            return data
                                ? data
                                : this.$__("Any");
                        },
                    },
                    {
                        title: this.$__("Overflow shelf"),
                        data: "overflow_shelf",
                        searchable: true,
                        orderable: true,
                        render: data => (data === true ? this.$__("Yes") : this.$__("No")),
                    },
                    {
                        title: this.$__("Locked"),
                        data: "locked",
                        searchable: true,
                        orderable: true,
                        render: data => (data === true ? this.$__("Yes") : this.$__("No")),
                    }
                ],
                actions: {
                    "-1": [
                        "edit",
                        {
                            editTab: {
                                text: this.$__("Edit in new tab"),
                                icon: "fa fa-external-link-alt",
                            },
                        },
                        {
                            delete: {
                                text: this.$__("Delete"),
                                icon: "fa fa-trash",
                            },
                        },
                    ],
                },
                url: "/api/v1/holds/pickup_shelves",
                options: {embed: "library,patron_category,holds_count", 
                          order: [[1, "asc"]]},
            },
            initialized: false,
            hold_pickup_shelves_any: 0,
            library_id: null,
        };
    },
    setup() {
        const { setWarning, setMessage, setError, setConfirmationDialog } =
            inject("mainStore");
        return {
            setWarning,
            setMessage,
            setError,
            setConfirmationDialog,
        };
    },
    beforeRouteEnter(to, from, next) {
        next(vm => {
            vm.anyHoldPickupShelves().then(() => (vm.initialized = true));
        });
    },
    watch: {
        initialized(newVal) {
            if (newVal) {
                this.$nextTick(() => {
                    const table = this.$el.querySelector("#hold_pickup_shelves_list .dataTable");
                    if (table) {
                        table.addEventListener("click", (event) => {
                            if (event.target && event.target.classList.contains("priority-arrow-down")) {
                                const priority = parseInt(event.target.getAttribute("data-priority"));
                                this.changePriority(event, priority + 1);
                            } else if (event.target && event.target.classList.contains("priority-arrow-up")) {
                                const priority = parseInt(event.target.getAttribute("data-priority"));
                                this.changePriority(event, priority - 1);
                            } else if (event.target && event.target.classList.contains("priority-arrow-last")) {
                                // Move the selected row to the last priority, shift others up
                                const table = event.target.closest("table");
                                if (table) {
                                    const rows = Array.from(table.querySelectorAll("tbody tr"));
                                    // Collect all shelf ids and priorities
                                    let priorities = rows.map(row => {
                                        const btn = row.querySelector('button[data-priority]');
                                        return {
                                            id: btn ? btn.getAttribute("data-id") : null,
                                            priority: btn ? parseInt(btn.getAttribute("data-priority")) : null,
                                            row: row
                                        };
                                    }).filter(p => p.id && !isNaN(p.priority));
                                    // Sort by priority ascending
                                    priorities.sort((a, b) => a.priority - b.priority);
                                    if (priorities.length < 2) return;
                                    // Find the selected id
                                    const selectedId = event.target.getAttribute("data-id");
                                    // Remove selected from array
                                    const selected = priorities.find(p => p.id === selectedId);
                                    priorities = priorities.filter(p => p.id !== selectedId);
                                    // Push selected to end if found
                                    if (selected) {
                                        priorities.push(selected);
                                        // Assign new priorities (1-based)
                                        this.batchUpdatePriorities(priorities.map((p, idx) => ({
                                            hold_pickup_shelf_id: p.id,
                                            priority: idx + 1
                                        })));
                                    }
                                }
                            } else if (event.target && event.target.classList.contains("priority-arrow-first")) {
                                // Reorder all priorities: last becomes first, others shift down
                                const table = event.target.closest("table");
                                if (table) {
                                    const rows = Array.from(table.querySelectorAll("tbody tr"));
                                    // Collect all shelf ids and priorities
                                    let priorities = rows.map(row => {
                                        const btn = row.querySelector('button[data-priority]');
                                        return {
                                            id: btn ? btn.getAttribute("data-id") : null,
                                            priority: btn ? parseInt(btn.getAttribute("data-priority")) : null,
                                            row: row
                                        };
                                    }).filter(p => p.id && !isNaN(p.priority));
                                    // Sort by priority ascending
                                    priorities.sort((a, b) => a.priority - b.priority);
                                    if (priorities.length < 2) return;
                                    // Find the selected id
                                    const selectedId = event.target.getAttribute("data-id");
                                    // Remove selected from array
                                    const selected = priorities.find(p => p.id === selectedId);
                                    priorities = priorities.filter(p => p.id !== selectedId);
                                    // Insert selected at the front if found
                                    if (selected) {
                                        priorities.unshift(selected);
                                        // Assign new priorities (1-based)
                                        this.batchUpdatePriorities(priorities.map((p, idx) => ({
                                            hold_pickup_shelf_id: p.id,
                                            priority: idx + 1
                                        })));
                                    }
                                }
                            }
                        });
                    }
                });
            }
        }
    },
    methods: {
        async anyHoldPickupShelves() {
            const client = APIClient.hold_pickup_shelves;
            await client.hold_pickup_shelves.getAll({}, {_page: 1, _per_page: 1}).then(
                hold_pickup_shelves => {
                    this.hold_pickup_shelves_any = hold_pickup_shelves.length;
                },
                error => {}
            );
        },
        fetchLibraryHoldPickupShelves(event) {
            const queryParams = this.library_id ? `library_id=${this.library_id}` : '';
            this.$refs.table.redraw("/api/v1/holds/pickup_shelves?" + queryParams);
        },
        newHoldPickupShelf() {
            this.$router.push({ name: "HoldPickupShelvesFormAdd" });
        },
        doEdit: function ({ hold_pickup_shelf_id }, dt, event) {
            this.$router.push({
            name: "HoldPickupShelvesFormAddEdit",
            params: { hold_pickup_shelf_id },
            });
        },
        doEditTab: function ({ hold_pickup_shelf_id }, dt, event) {
            const url = this.$router.resolve({
                name: "HoldPickupShelvesFormAddEdit",
                params: { hold_pickup_shelf_id },
            }).href;
            window.open(url, '_blank');
        },
        doDelete: function (hold_pickup_shelf, dt, event) {
            this.setConfirmationDialog(
                {
                    title: this.$__(
                        "Are you sure you want to delete this hold pickup shelf?"
                    ),
                    message: hold_pickup_shelf.shelf_name,
                    accept_label: this.$__("Yes, delete"),
                    cancel_label: this.$__("No, do not delete"),
                },
                () => {
                    const client = APIClient.hold_pickup_shelves;
                    client.hold_pickup_shelves.delete(hold_pickup_shelf.hold_pickup_shelf_id).then(
                        success => {
                            this.setMessage(
                                this.$__(
                                    "Hold pickup shelf '%s' deleted"
                                ).format(hold_pickup_shelf.shelf_name),
                                true
                            );
                            dt.draw();
                        },
                        error => {}
                    );
                }
            );
        },
        changePriority: function (event, priority) {
            const input = event.target;
            const hold_pickup_shelf_id = input.getAttribute("data-id");
            if (isNaN(priority) || priority < 1) {
                this.setWarning(this.$__("Priority must be a positive integer"));
                return;
            }
            const client = APIClient.hold_pickup_shelves;
            client.hold_pickup_shelves.patch(hold_pickup_shelf_id, {priority: priority}).then(
                success => {
                    this.setMessage(this.$__("Priority updated successfully"));
                    this.$refs.table.redraw("/api/v1/holds/pickup_shelves");
                },
                error => {
                    this.setError(this.$__("Failed to update priority"));
                }
            );
        },
        batchUpdatePriorities: function (priorities) {
            const client = APIClient.hold_pickup_shelves;
            client.batch_update_priority.update(priorities).then(
                success => {
                    this.setMessage(this.$__("Priorities updated successfully"));
                    this.$refs.table.redraw("/api/v1/holds/pickup_shelves");
                },
                error => {
                    this.setError(this.$__("Failed to update priorities"));
                }
            );
        },
    },
    components: {
        KohaTable,
        Toolbar,
        ToolbarButton,
    },
};
</script>
