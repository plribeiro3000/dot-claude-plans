// SOURCE: app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts
// Lines 213–227 — getSignature() method and component-level signature field.
// This shows that signature image URL is fetched via a secondary GraphQL query AFTER
// the plan statement loads. The URL is a presigned S3 URL returned by temporarySignature query.

  signature: { id: number; url: string } | null = null;

  // ...

  getSignature() {
    const signatureId = this.planStatement?.acceptment?.signature?.id;

    if (!signatureId) {
      return;
    }

    this.temporarySignatureService.get(signatureId).valueChanges.subscribe((response: any) => {
      if (!response?.data?.temporarySignature) {
        return;
      }

      this.signature = response.data.temporarySignature;
    });
  }

// SOURCE: app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts
// Lines 237–239 — print() method.
// The existing "print" button simply calls window.print(). No server-side PDF, no capture logic.

  print() {
    window.print();
  }
