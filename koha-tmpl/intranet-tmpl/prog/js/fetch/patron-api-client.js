export class PatronAPIClient {
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/api/v1/patrons/",
        });
        this.categoriesHttpClient = new HttpClient({
            baseURL: "/api/v1/patron_categories/",
        });
    }

    get patrons() {
        return {
            get: id =>
                this.httpClient.get({
                    endpoint: id,
                }),
        };
    }
    
    get patron_categories() {
        return {
            getAll: (query, params) =>
                this.categoriesHttpClient.get({
                    endpoint: "",
                    query,
                    params,
                    headers: {},
                }),
        };
    }
}

export default PatronAPIClient;
