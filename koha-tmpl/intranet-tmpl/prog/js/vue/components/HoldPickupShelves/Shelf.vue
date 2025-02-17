<template>
    <div v-if="!error" class="alert alert-info">
        <span v-if="loading"><i class="fas fa-spinner fa-spin"></i> {{ $__('Loading...') }}</span>
        <span v-else><i class="fas fa-info-circle"></i> {{ $__('Selected pickup shelf') }}: <b>{{ hold_pickup_shelf.shelf_name }}</b></span>
    </div>
</template>
<script>
import { inject } from "vue";
import { APIClient } from "../../fetch/api-client.js";
export default {
    name: "Shelf",
    props: {
        hold_pickup_shelf_id: {
            type: Number,
            required: true
        }
    },
    setup() {
        const { setError } = inject("mainStore");
        return {
            setError,
        };
    },
    data() {
        return {
            hold_pickup_shelf: {},
            loading: true,
            error: false,
        }
    },
    mounted() {
        this.getShelf();
    },
    methods: {
        async getShelf() {
            try {
                const client = APIClient.hold_pickup_shelves;
                this.hold_pickup_shelf = await client.hold_pickup_shelves.get(this.hold_pickup_shelf_id);
                this.loading = false;
            } catch (error) {
                this.error = true;
                this.setError(this.$__("Error fetching pickup shelf data") + ": " + error.message);
                this.loading = false;
            }
        }
    },
}
</script>