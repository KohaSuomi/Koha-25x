<template>
    <div>
        <div id="sub-header">
            <Breadcrumbs></Breadcrumbs>
            <Help />
        </div>
        <div class="main container-fluid">
            <div class="row">
                <div class="col-md-10 col-md-offset-1 col-lg-8 col-lg-offset-2">
                    <main>
                        <Dialog></Dialog>
                        <router-view :libraries="libraries" :categories="categories" :biblio_level_itemtypes="biblio_level_itemtypes"></router-view>
                    </main>
                </div>
            </div>
        </div>
    </div>
</template>

<script>
import Breadcrumbs from "../../Breadcrumbs.vue";
import Help from "../../Help.vue";
import Dialog from "../../Dialog.vue";
import { APIClient } from "../../../fetch/api-client.js";

export default {
    components: {
        Breadcrumbs,
        Dialog,
        Help,
    },
    data() {
        return {
            libraries: [],
            categories: [],
            biblio_level_itemtypes: [],
            shelf_count: 0,
        }
    },
    async beforeMount() {
        const client = APIClient;
        const [libraries, categories, biblio_level_itemtypes] = await Promise.all([
            client.libraries.libraries.getAll(),
            client.patron.patron_categories.getAll(),
            client.hold_pickup_shelves.biblio_level_itemtypes.getAll()
        ]);
        this.libraries = libraries;
        this.categories = categories;
        this.biblio_level_itemtypes = biblio_level_itemtypes;
    },
};
</script>

<style></style>
