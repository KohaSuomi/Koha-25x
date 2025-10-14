<template>
    <div :class="{'mt-2': error }">
        <div v-if="loading" class="alert alert-info">
            <i class="fas fa-spinner fa-spin"></i> {{ $__('Loading...') }}
        </div>
        <div v-else-if="shelves.length > 0">
            <div class="row">
                <div class="col-md-12">
                    <p><b>{{ $__('Select a pickup shelf') }}</b></p>
                </div>
                <div class="col-md-12" v-if="notification">
                    <div class="alert alert-warning">
                        <i class="fas fa-info-circle"></i> <b>{{ notification }}</b>
                    </div>
                </div>
                <div class="col-md-6">
                    <select id="hold_pickup_shelf_id" class="form-control me-2" v-model="hold_pickup_shelf_id" @change="changeShelf($event)" :disabled="patron_selected_shelf">
                        <option value=""></option>
                        <option v-for="shelf in shelves" :key="shelf.hold_pickup_shelf_id" :value="shelf.hold_pickup_shelf_id">
                            {{ shelf.shelf_name }}
                        </option>
                    </select>
                </div>
                <div class="col-md-2 no-gutters">
                    <button class="btn btn-success me-2" @click="selectShelf($event)" :disabled="!hold_pickup_shelf_id || patron_selected_shelf || special_shelf">
                        <i class="fas fa-check"></i>
                    </button>
                    <button class="btn btn-primary" @click="lockShelf($event)" :disabled="disable_lock_button">
                        <i class="fas fa-lock"></i>
                    </button>
                </div>
            </div>
        </div>
        <div v-else>
            <div class="alert alert-info">
                <i class="fas fa-info-circle"></i> {{ $__('No pickup shelves available') }}
            </div>
        </div>
    </div>
</template>
<style scoped>
    .mt-2 {
        margin-top: 15px !important;
    }
    .no-gutters {
        margin-right: 0 !important;
        margin-left: 0 !important;
        padding-right: 0 !important;
        padding-left: 0 !important;
    }
    .close {
        float: right !important;
        font-size: 18px !important;
        font-weight: bold !important;
        line-height: 1 !important;
        color: #000 !important;
        text-shadow: 0 1px 0 #fff !important;
    }
</style>
<script>
import { inject } from "vue";
import { APIClient } from "../../fetch/api-client.js";
export default {
    props: {
        biblio_id: {
            type: Number,
            required: true
        },
        library_id: {
            type: String,
            required: true
        },
        patron_id: {
            type: Number,
            required: true
        },
        logged_in_user_borrowernumber: {
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
            shelves: [],
            hold_pickup_shelf: {},
            hold_pickup_shelf_id: null,
            selected_shelf_id: null,
            notification: null,
            disable_lock_button: false,
            patron_selected_shelf: false,
            special_shelf: false,
            loading: true,
            confirmed: false,
            error: false
        }
    },
    async mounted() {
        this.getShelves();
        this.handleConfirmButton();
    },
    watch: {
        hold_pickup_shelf_id() {
            const hiddenInput = document.getElementsByName("hold_pickup_shelf_id")[0];
            if (hiddenInput) {
                hiddenInput.value = this.hold_pickup_shelf_id;
            }
        }
    },
    methods: {
        async getShelves() {
            try {
                const client = APIClient.hold_pickup_shelves;
                let shelves = await client.available.getAll({}, { biblio_id: this.biblio_id, library_id: this.library_id, patron_id: this.patron_id });
                // Show shelf which has patron_id, otherwise filter out shelves which have patron_id
                const userShelf = shelves.find(shelf => parseInt(shelf.patron_id) === parseInt(this.logged_in_user_borrowernumber));
                if (userShelf) {
                    this.patron_selected_shelf = true;
                    this.shelves = [userShelf];
                    this.hold_pickup_shelf_id = userShelf.hold_pickup_shelf_id;
                    this.hold_pickup_shelf = userShelf;
                } else {
                    // Only show shelves without patron_id
                    this.patron_selected_shelf = false;
                    this.shelves = shelves.filter(shelf => !shelf.patron_id);
                    let found = this.shelves.find(shelf => shelf.hold_pickup_shelf_id === this.hold_pickup_shelf_id);
                    if (found) {
                        this.hold_pickup_shelf = found;
                    } else {
                        this.hold_pickup_shelf_id = this.shelves[0].hold_pickup_shelf_id;
                        this.hold_pickup_shelf = this.shelves[0];
                    }
                    
                }
                this.loading = false;
                if (this.hold_pickup_shelf.holds_count === 0) {
                    this.disable_lock_button = true;
                }
                this.specialShelf();
            } catch (error) {
                this.shelves = [];
                this.error = true;
                this.setError(this.$__("Error fetching pickup shelves") + ": " + error.message);
                this.loading = false;
            }
        },
        selectShelf(e) {
            this.error = false;
            e.preventDefault();
            const client = APIClient.hold_pickup_shelves;
            if (this.hold_pickup_shelf_id) {
                client.hold_pickup_shelves.patch(this.hold_pickup_shelf_id, { patron_id: this.logged_in_user_borrowernumber })
                    .then(() => {
                        this.getShelves();
                    })
                    .catch(error => {
                        this.error = true;
                        this.setError(this.$__("Error selecting pickup shelf") + ": " + error.message);
                    });
            }
        },
        lockShelf(e) {
            this.error = false;
            e.preventDefault();
            const client = APIClient.hold_pickup_shelves;
            if (this.hold_pickup_shelf_id) {
                const locked_date = new Date();
                client.hold_pickup_shelves.patch(this.hold_pickup_shelf_id, { locked: true, locked_date: locked_date, patron_id: null })
                    .then(() => {
                        this.getShelves();
                    })
                    .catch(error => {
                        this.error = true;
                        this.setError(this.$__("Error locking pickup shelf") + ": " + error.message);
                    });
            }
        },
        specialShelf() {
            if (this.hold_pickup_shelf && this.hold_pickup_shelf.overflow_shelf) {
                this.special_shelf = true;
            } else {
                this.special_shelf = false;
            }
        },
        changeShelf(e) {
            this.hold_pickup_shelf = this.shelves.find(shelf => shelf.hold_pickup_shelf_id === this.hold_pickup_shelf_id);
            if (!this.hold_pickup_shelf || this.hold_pickup_shelf.holds_count === 0) {
                this.disable_lock_button = true;
            } else {
                this.disable_lock_button = false;
            }
            this.specialShelf();
        },
        handleConfirmButton() {
            // Wait for DOM to be ready
            this.$nextTick(() => {
                const Btn = document.getElementById("hold-found-modal-confirm");
                const PrintBtn = document.getElementById("hold-pickup-shelf-print");
                const form = document.getElementById("hold-found-modal-form");
                // If the button exists, override its click event
                if (Btn) {
                    // Add your custom click handler
                    Btn.addEventListener("click", (e) => {
                        e.preventDefault();
                        // Call your API here, then submit if needed
                        this.handleCustomConfirm().then(() => {
                            if (!this.confirmed) {
                                return; // Do not submit if not confirmed
                            }
                            // Submit the form
                            if (form) {
                                form.submit();
                            }
                        });
                    });
                }
                if (PrintBtn) {
                    PrintBtn.addEventListener("click", (e) => {
                        e.preventDefault();
                        this.handleCustomConfirm().then(() => {
                            if (!this.confirmed) {
                                return; // Do not submit if not confirmed
                            }
                            if (form) {
                                form.print_slip.value = 1;
                                form.submit();
                            }
                        });
                    });
                }
                
            });
        },
        async handleCustomConfirm() {
            const hold_pickup_shelf_id = document.getElementsByName("hold_pickup_shelf_id")[0];
            this.notification = null;
            this.selected_shelf_id = hold_pickup_shelf_id.value;
            if (this.selected_shelf_id !== "") {
                // Refresh shelves to ensure the selected shelf is still available
                await this.getShelves();
                if (parseInt(this.selected_shelf_id) !== parseInt(this.hold_pickup_shelf_id)) {
                    this.notification = this.$__("Selected shelf is unavailable. Please choose another shelf.");
                } else {
                    this.confirmed = true;
                }
            } else {
                this.confirmed = true;
            }
        }
    }
};
</script>