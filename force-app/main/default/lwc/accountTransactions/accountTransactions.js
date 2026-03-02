import { LightningElement, api, track } from "lwc";
import getAccountTransactions from "@salesforce/apex/TransactionController.getAccountTransactions";

const COLUMNS = [
  {
    label: "Transaction ID",
    fieldName: "transactionId",
    type: "text",
    sortable: true,
    cellAttributes: { class: "slds-text-font_monospace" }
  },
  {
    label: "API Account ID",
    fieldName: "accountId",
    type: "text",
    sortable: true
  },
  {
    label: "Message Parts",
    fieldName: "messageParts",
    type: "number",
    sortable: true,
    cellAttributes: { alignment: "left" }
  },
  {
    label: "Date (local time)",
    fieldName: "transactionDate",
    type: "date",
    sortable: true,
    typeAttributes: {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }
  }
];

export default class TransactionViewer extends LightningElement {

  @api recordId;

  @track transactions = [];
  @track isLoading = false;
  @track errorMessage = "";
  @track hasSearched = false;

  startDate = "";
  endDate = "";
  sortedBy = "transactionDate";
  sortedDirection = "desc";
  columns = COLUMNS;

  get hasTransactions() {
    return this.transactions.length > 0;
  }

  get showEmpty() {
    return this.hasSearched && !this.isLoading && !this.hasTransactions && !this.errorMessage;
  }

  get showInitialState() {
    return !this.hasSearched && !this.isLoading && !this.errorMessage;
  }

  get totalTransactions() {
    return this.transactions.length;
  }

  get totalMessageParts() {
    return this.transactions.reduce((sum, t) => sum + (t.messageParts || 0), 0);
  }

  get uniqueAccountCount() {
    return new Set(this.transactions.map(t => t.accountId)).size;
  }

  handleStartDate(event) {
    this.startDate = event.detail.value;
  }

  handleEndDate(event) {
    this.endDate = event.detail.value;
  }

  clearResults() {
    this.transactions = [];
    this.errorMessage = "";
    this.hasSearched = false;
  }

  loadTransactions() {
    // Client-side validation
    if (!this.startDate) {
      this.errorMessage = "Please select a Start Date before loading transactions.";
      return;
    }
    if (this.endDate && this.endDate < this.startDate) {
      this.errorMessage = "End Date cannot be earlier than Start Date.";
      return;
    }

    this.isLoading = true;
    this.errorMessage = "";
    this.transactions = [];
    this.hasSearched = false;

    getAccountTransactions({
      accountId: this.recordId,
      startDate: this.startDate,
      endDate: this.endDate ? this.endDate : null
    }).then(result => {
      this.transactions = this.sortData(result.transactions || [], this.sortedBy, this.sortedDirection);
      this.hasSearched = true;
    }).catch(error => {
      this.errorMessage = this.extractErrorMessage(error);
      this.hasSearched = true;
    }).finally(() => {
      this.isLoading = false;
    });
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortedDirection = event.detail.sortDirection;
    this.transactions = this.sortData([...this.transactions], this.sortedBy, this.sortedDirection);
  }

  sortData(data, field, direction) {
    const cloned = [...data];
    const modifier = direction === "asc" ? 1 : -1;
    cloned.sort((a, b) => {
      const valA = a[field] ?? "";
      const valB = b[field] ?? "";
      if (valA < valB) return -1 * modifier;
      if (valA > valB) return 1 * modifier;
      return 0;
    });
    return cloned;
  }

  extractErrorMessage(error) {
    if (error?.body?.message) return error.body.message;
    if (error?.message) return error.message;
    if (typeof error === "string") return error;
    return "An unexpected error occurred. Please try again.";
  }
}
