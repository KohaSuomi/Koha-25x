import { markRaw } from "vue";
import HoldPickupShelvesFormAdd from "../../components/Admin/HoldPickupShelves/FormAdd.vue";
import HoldPickupShelvesList from "../../components/Admin/HoldPickupShelves/List.vue";
import { $__ } from "../../i18n";

export default {
    title: $__("Administration"),
    path: "",
    href: "/cgi-bin/koha/admin/admin-home.pl",
    is_base: true,
    is_default: true,
    children: [
        {
            title: $__("Hold pickup shelves"),
            path: "/cgi-bin/koha/admin/hold_pickup_shelves",
            is_end_node: true,
            children: [
                {
                    path: "",
                    name: "HoldPickupShelvesList",
                    component: markRaw(HoldPickupShelvesList),
                },
                {
                    component: markRaw(HoldPickupShelvesFormAdd),
                    name: "HoldPickupShelvesFormAdd",
                    path: "add",
                    title: $__("Add hold pickup shelf"),
                },
                {
                    component: markRaw(HoldPickupShelvesFormAdd),
                    name: "HoldPickupShelvesFormAddEdit",
                    path: "edit/:hold_pickup_shelf_id",
                    title: $__("Edit hold pickup shelf"),
                },
            ],
        },
    ],
};
