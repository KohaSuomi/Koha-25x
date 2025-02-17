export class HoldPickupShelvesAPIClient {
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/api/v1/holds/pickup_shelves",
        });
    }

    get hold_pickup_shelves() {
        return {
            create: hold_pickup_shelf =>
                this.httpClient.post({
                    endpoint: "",
                    body: hold_pickup_shelf,
                }),
            delete: id =>
                this.httpClient.delete({
                    endpoint: "/" + id,
                }),
            update: (hold_pickup_shelf, id) =>
                this.httpClient.put({
                    endpoint: "/" + id,
                    body: hold_pickup_shelf,
                }),
            patch: (id, body) =>
                this.httpClient.patch({
                    endpoint: "/" + id,
                    body,
                }),
            get: id =>
                this.httpClient.get({
                    endpoint: "/" + id,
                }),
            getAll: (query, params) =>
                this.httpClient.getAll({
                    endpoint: "/",
                    query,
                    params,
                    headers: {},
                }),
        };  
    }
    get available() {
        return {
            getAll: (query, params) =>
                this.httpClient.getAll({
                    endpoint: "/available",
                    query,
                    params,
                    headers: {},
                }),
        }
    }

    get biblio_level_itemtypes() {
        return {
            getAll: (query, params) =>
                this.httpClient.getAll({
                    endpoint: "/biblio_level_itemtypes",
                    query,
                    params,
                    headers: {},
                }),
        }
    }

    get batch_update_priority() {
        return {
            update: (body) =>
                this.httpClient.post({
                    endpoint: "/priority",
                    body,
                }),
        }
    }
}

export default HoldPickupShelvesAPIClient;
