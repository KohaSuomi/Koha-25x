<template>
    <div v-if="!initialized">{{ $__("Loading") }}</div>
    <div v-else id="hold_pickup_shelves_edit">
        <h1 v-if="hold_pickup_shelf.shelf_name">
            {{
                $__("Edit pickup shelf #%s").format(
                    hold_pickup_shelf.shelf_name
                )
            }}
        </h1>
        <h1 v-else>{{ $__("Add pickup shelf") }}</h1>
        <form @submit="onSubmit($event)">
            <fieldset class="rows">
                <ol>
                    <li>
                        <label class="required" for="library_id">
                            {{ $__("Library ID") }}:
                        </label>
                        <select
                            id="library_id"
                            v-model="hold_pickup_shelf.library_id"
                            required
                        >
                            <option
                                v-for="library in libraries"
                                :value="library.library_id"
                                :key="library.library_id"
                                >{{ library.name }}</option
                            >
                        </select>
                        <span class="required">{{ $__("Required") }}</span>
                    </li>
                    <li>
                        <label class="required" for="shelf_name">
                            {{ $__("Shelf name") }}:
                        </label>
                        <input
                            id="shelf_name"
                            v-model="hold_pickup_shelf.shelf_name"
                            required
                        />
                        <span class="required">{{ $__("Required") }}</span>
                    </li>
                    <li>
                        <label class="required" for="max_items">
                            {{ $__("Max items") }}:
                        </label>
                        <input
                            id="max_items"
                            v-model="hold_pickup_shelf.max_items"
                            required
                        />
                        <span class="required">{{ $__("Required") }}</span>
                    </li>
                    <li>
                        <label for="weekday">
                            {{ $__("Weekday") }}:
                        </label>
                        <select
                            id="weekday"
                            v-model="hold_pickup_shelf.weekday"
                        >
                            <option :value="null"></option>
                            <option
                                v-for="weekday in weekdays"
                                :value="weekday.id"
                                :key="weekday.id"
                                >{{ weekday.name }}</option
                            >
                        </select>
                    </li>
                    <li>
                        <label for="biblio_itemtype">
                            {{ $__("Biblio level itemtype") }}:
                        </label>
                        <select
                            id="biblio_itemtype"
                            v-model="hold_pickup_shelf.biblio_itemtype"
                        >
                            <option :value="null"></option>
                            <option
                                v-for="itemtype in biblio_level_itemtypes"
                                :value="itemtype.id"
                                :key="itemtype.id"
                                >{{ itemtype.name }}</option
                            >
                        </select>
                    </li>
                    <li>
                        <label for="categorycode">
                            {{ $__("Category") }}:
                        </label>
                        <select
                            id="patron_category_id"
                            v-model="hold_pickup_shelf.patron_category_id"
                        >   
                            <option :value="null"></option>
                            <option
                                v-for="category in categories"
                                :value="category.patron_category_id"
                                :key="category.patron_category_id"
                                >{{ category.name }}</option
                            >
                        </select>
                    </li>
                    <li>
                        <label for="overflow_shelf">
                            {{ $__("Overflow shelf") }}:
                        </label>
                        <input
                            id="overflow_shelf"
                            v-model="hold_pickup_shelf.overflow_shelf"
                            type="checkbox"
                        />
                    </li>
                    <li>
                        <label for="locked">
                            {{ $__("Lock shelf") }}:
                        </label>
                        <input
                            id="locked"
                            v-model="hold_pickup_shelf.locked"
                            type="checkbox"
                        />
                    </li>
                </ol>
            </fieldset>
            <fieldset class="action">
                <input
                    type="submit"
                    class="btn btn-primary"
                    :value="$__('Submit')"
                />
                <router-link
                    :to="{ name: 'HoldPickupShelvesList' }"
                    role="button"
                    class="cancel"
                    >{{ $__("Cancel") }}</router-link
                >
            </fieldset>
        </form>
    </div>
</template>

<script>
import { inject } from "vue";
import { setMessage, setError, setWarning } from "../../../messages";
import { APIClient } from "../../../fetch/api-client.js";

export default {
    props: {
        libraries: Array,
        categories: Array,
        biblio_level_itemtypes: Array,
    },
    setup() {
        const { setMessage } = inject("mainStore");
        return {
            setMessage,
        };
    },
    data() {
        return {
            hold_pickup_shelf: {
                hold_pickup_shelf_id: null,
                shelf_name: "",
                library_id: "",
                max_items: 0,
            },
            initialized: false,
            weekdays: [
                { id: 'Monday', name: this.$__("Monday") },
                { id: 'Tuesday', name: this.$__("Tuesday") },
                { id: 'Wednesday', name: this.$__("Wednesday") },
                { id: 'Thursday', name: this.$__("Thursday") },
                { id: 'Friday', name: this.$__("Friday") },
                { id: 'Saturday', name: this.$__("Saturday") },
                { id: 'Sunday', name: this.$__("Sunday") },
            ],
        };
    },
    beforeRouteEnter(to, from, next) {
        next(vm => {
            if (to.params.hold_pickup_shelf_id) {
                vm.getHoldPickupShelf(to.params.hold_pickup_shelf_id);
            } else {
                vm.initialized = true;
            }
        });
    },
    methods: {
        async getHoldPickupShelf(hold_pickup_shelf_id) {
            const client = APIClient.hold_pickup_shelves;
            client.hold_pickup_shelves.get(hold_pickup_shelf_id).then(
                hold_pickup_shelf => {
                    this.hold_pickup_shelf = hold_pickup_shelf;
                    this.hold_pickup_shelf_id = hold_pickup_shelf_id;
                    this.initialized = true;
                },
                error => {}
            );
        },
        onSubmit(e) {
            e.preventDefault();
            const client = APIClient.hold_pickup_shelves;
            let response;
            // RO attribute
            delete this.hold_pickup_shelf.hold_pickup_shelf_id;
            if (this.hold_pickup_shelf_id) {
                // update
                response = client.hold_pickup_shelves
                    .update(this.hold_pickup_shelf, this.hold_pickup_shelf_id)
                    .then(
                        success => {
                            setMessage(this.$__("Hold pickup shelf updated!"));
                            this.$router.push({ name: "HoldPickupShelvesList" });
                        },
                        error => {}
                    );
            } else {
                response = client.hold_pickup_shelves
                    .create(this.hold_pickup_shelf)
                    .then(
                        success => {
                            setMessage(this.$__("Hold pickup shelf created!"));
                            this.$router.push({ name: "HoldPickupShelvesList" });
                        },
                        error => {}
                    );
            }
        },
    },
};
</script>
