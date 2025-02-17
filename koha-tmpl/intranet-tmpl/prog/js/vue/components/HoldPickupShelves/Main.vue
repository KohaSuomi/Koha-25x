<template>
    <Dialog></Dialog>
    <component :is="componentToRender" 
            :biblio_id="biblio_id" 
            :library_id="library_id" 
            :patron_id="patron_id"
            :logged_in_user_borrowernumber="logged_in_user_borrowernumber"
            :hold_pickup_shelf_id="shelf_id" />
</template>
<script>
import { inject } from "vue";
import Dialog from "../Dialog.vue";
import Shelf from "./Shelf.vue";
import Select from "./Select.vue";

export default {
    setup() {
        const mainStore = inject("mainStore")
        const { setMessage, setError } = mainStore

        return {
            setMessage,
            setError,
        }
    },
    props: {
        biblio_id: {
            type: Number,
            required: false
        },
        library_id: {
            type: String,
            required: false
        },
        patron_id: {
            type: Number,
            required: false
        },
        logged_in_user_borrowernumber: {
            type: Number,
            required: false
        },
        shelf_id: {
            type: Number,
            required: false
        }
    },
    components: {
        Dialog,
        Shelf,
        Select
    },
    computed: {
        componentToRender() {
            return this.shelf_id ? "Shelf" : "Select";
        }
    }
};
</script>