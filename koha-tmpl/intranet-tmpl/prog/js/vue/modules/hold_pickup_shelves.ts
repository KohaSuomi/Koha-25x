import { createApp } from "vue";
import { createPinia } from "pinia";

import { library } from "@fortawesome/fontawesome-svg-core";
import {
    faPlus,
    faMinus,
    faPencil,
    faTrash,
    faSpinner,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/vue-fontawesome";
import vSelect from "vue-select";
import { useMainStore } from "../stores/main";

library.add(faPlus, faMinus, faPencil, faTrash, faSpinner);

const pinia = createPinia();
const mainStore = useMainStore(pinia);

import App from "../components/HoldPickupShelves/Main.vue";
import i18n from "../i18n";

const view = document.getElementById('hold-pickup-shelves-view');
if (view) {
    const app = createApp(App, {
        library_id: view.getAttribute('data-library-id'),
        biblio_id: view.getAttribute('data-biblio-id'),
        patron_id: view.getAttribute('data-patron-id'),
        logged_in_user_borrowernumber: view.getAttribute('data-logged-in-user-borrowernumber'),
        shelf_id: view.getAttribute('data-shelf-id'),
    });
    const rootComponent = app
        .use(i18n)
        .use(pinia)
        .component("font-awesome-icon", FontAwesomeIcon)
        .component("v-select", vSelect);

    app.config.unwrapInjectedRef = true;
    app.provide("mainStore", mainStore);
    app.mount(view);
}