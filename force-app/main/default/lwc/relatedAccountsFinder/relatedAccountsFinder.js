import { LightningElement, api, wire, track } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getRelatedAccountsByDomain from "@salesforce/apex/RelatedAccountsController.getRelatedAccountsByDomain";

const COLUMNS = [
  {
    label: "Account Name",
    fieldName: "name",
    type: "text",
    sortable: true
  },
  {
    label: "Matched Domain",
    fieldName: "matchedDomain",
    type: "text",
    sortable: true
  }
];

export default class RelatedAccountsFinder extends LightningElement {

  @api recordId;

  columns = COLUMNS;
  sortedBy = "accountName";
  sortedDirection = "asc";

  @track accounts = [];
  @track error = "";
  @track isLoading = true;

  // Holds the wired result reference so refreshApex can re-trigger it
  _wiredResult;

  @wire(getRelatedAccountsByDomain, { accountId: "$recordId" })
  wiredAccounts(result) {
    this._wiredResult = result;
    this.isLoading = false;

    if (result.data !== undefined) {
      this.accounts = this.sortData(result.data || [], this.sortedBy, this.sortedDirection);
      this.error = "";
    }
    if (result.error) {
      this.error = this.extractErrorMessage(result.error);
      this.accounts = [];
    }
  }

  get hasAccounts() {
    return !this.isLoading && !this.error && this.accounts.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.error && this.accounts.length === 0;
  }

  handleRefresh() {
    this.isLoading = true;
    refreshApex(this._wiredResult)
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortedDirection = event.detail.sortDirection;
    this.accounts = this.sortData([...this.accounts], this.sortedBy, this.sortedDirection);
  }

  sortData(data, field, direction) {
    const modifier = direction === "asc" ? 1 : -1;
    return [...data].sort((a, b) => {
      const va = (a[field] ?? "").toString().toLowerCase();
      const vb = (b[field] ?? "").toString().toLowerCase();
      if (va < vb) return -1 * modifier;
      if (va > vb) return 1 * modifier;
      return 0;
    });
  }

  extractErrorMessage(error) {
    if (error?.body?.message) return error.body.message;
    if (error?.message) return error.message;
    if (typeof error === "string") return error;
    return "An unexpected error occurred.";
  }
}
