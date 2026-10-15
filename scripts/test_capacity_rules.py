"""Synthetic schema-2 capacity and hostile-write checks on the local emulator.

Run after test_firestore_rules.py. This test resets demo-phase1 only; no private
documents or production endpoints are used. Client hash/sequence validation is
covered separately by Dart tests; rules enforce typed, immutable staged rows.
"""
import base64
import copy
import hashlib
import json
from pathlib import Path

from test_firestore_rules import BASE, NOW, PROJECT, commit, request, write


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def stage(family, subject, rows, *, generation=0, revision=1, year=2024,
          ticker='', account='', sale_revision=0, reviewed=False):
    metadata = dict(schemaVersion=1, userId='owner', family=family,
        subjectId=subject, yearStart=year, revision=revision, generation=generation,
        ticker=ticker, accountNumber=account, saleRevision=sale_revision,
        reviewed=reviewed, count=len(rows), hash=digest(rows))
    identifier = digest(metadata)
    metadata.update(state='staging', createdAt=NOW)
    commit([write('revision_details/' + identifier, metadata)])
    for start in range(0, len(rows), 4):
        commit([write(f'revision_details/{identifier}/records/{i}', dict(rows[i], index=i))
                for i in range(start, min(start + 4, len(rows)))])
    return identifier, metadata, dict(detailSetId=identifier, detailCount=len(rows), detailHash=metadata['hash'])


def publish(identifier, metadata):
    return write('revision_details/' + identifier, dict(metadata, state='published'))


def main():
    rules = (Path(__file__).resolve().parents[1] / 'firestore.rules').read_text(encoding='utf-8-sig')
    request('PUT', f'/emulator/v1/projects/{PROJECT}:securityRules',
        {'rules': {'files': [{'content': rules}]}}, uid=None)
    request('DELETE', f'/emulator/v1/{BASE}', uid=None)
    period = dict(start='2024-07-01', endExclusive='2025-07-01',
        classification='resident', evidence='Synthetic residency', reviewed=True)
    rows = [dict(kind='residency', payload=period) for _ in range(12)]
    identifier, metadata, header = stage('workspace', '2024', rows)
    workspace = dict(schemaVersion=2, userId='owner', yearStart=2024,
        revision=1, status='draft', amendmentReason='', cgtSnapshotId='',
        sectionStates={}, sectionEvidence={}, prefill={}, updatedAt=NOW, **header)
    workspace_writes = [write('tax_years/2024', workspace),
        write('tax_years/2024/revisions/1', workspace),
        write('tax_workspace_metadata/current', {'generation': 1})]
    commit(workspace_writes, expected=403)  # A staging manifest cannot be consumed.
    commit([publish(identifier, metadata)], expected=403)  # Publication requires its parent transaction.
    commit(workspace_writes + [publish(identifier, metadata)])
    commit([write(f'revision_details/{identifier}/records/0', dict(rows[0], index=0))], expected=403)
    request('GET', f'/v1/{BASE}/users/owner/revision_details/{identifier}', uid='other', expected=403)
    request('GET', f'/v1/{BASE}/users/owner/revision_details/{identifier}/records/0', uid=None, expected=403)
    bad_id, bad_meta, _ = stage('workspace', '2024', [], generation=1, revision=2)
    bad_meta['count'] = 1
    # New stage with one expected row; malformed currency/type fields stay denied.
    bad_id = digest(bad_meta)
    commit([write('revision_details/' + bad_id, bad_meta)])
    malformed = dict(index=0, kind='i1', payload=dict(date='2025-01-01',
        assetReference='Synthetic asset', marketValue='NaN', costBase='0', reducedCostBase='0',
        classification='nonTAP', election='recognise', evidence='Synthetic',
        adviserReference='Synthetic adviser', reviewed=True))
    commit([write(f'revision_details/{bad_id}/records/0', malformed)], expected=403)
    commit([write(f'revision_details/{bad_id}/records/0', dict(index=0, kind='unknown', payload={}))], expected=403)
    commit([write(f'revision_details/{bad_id}/records/1', dict(index=1, kind='residency', payload=period))], expected=403)
    # Seven individually bounded records carry an archive larger than Firestore's single-document limit.
    source = json.dumps({'syntheticWorkpaper': 'x' * 1100000}).encode()
    chunks = [dict(kind='archiveChunk', payload={'data': base64.b64encode(source[i:i+180000]).decode()})
              for i in range(0, len(source), 180000)]
    snapshot_id = 'imported-' + 'b' * 64
    archive_id, archive_meta, archive_header = stage('archive', snapshot_id, chunks,
        generation=1, revision=0)
    snapshot = dict(schemaVersion=2, userId='owner', yearStart=2024, kind='imported',
        createdAt=NOW, payloadHeader={}, **archive_header)
    commit([write('tax_years/2024/snapshots/' + snapshot_id, snapshot), publish(archive_id, archive_meta)])
    commit([write('tax_years/2024/snapshots/' + snapshot_id, snapshot)], expected=403)
    # Reviewed fund detail rows validate real referenced acquisitions without an array cap.
    fact = dict(userId='owner', ticker='SYN', accountNumber='synthetic', transactionType='BUY',
        tradeDate=NOW, tradeDateIso='2025-01-01', isReviewed=True, isLocked=False,
        isVoided=False, revision=1)
    commit([write('investment_transactions/buy', fact)], admin=True)
    adjustment = dict(parcelId='buy', date='2025-06-30', amount='1',
        evidenceReference='Synthetic AMIT adjustment', beforeSaleId=None, units=None)
    fund_rows = [dict(kind='fundAdjustment', payload=adjustment) for _ in range(12)]
    fund_id, fund_meta, fund_header = stage('fund', 'synthetic-fund', fund_rows,
        ticker='SYN', account='synthetic', reviewed=True)
    components = {key: '0' for key in ['australianIncome', 'foreignIncome', 'frankingCredits',
        'foreignTaxOffset', 'withholding', 'cashDistributions', 'discountedCapitalGain',
        'otherCapitalGain', 'grossCapitalGain', 'amitShortfall', 'amitExcess', 'taxDeferred', 'taxFree', 'taxExempt']}
    fund = dict(schemaVersion=2, userId='owner', ticker='SYN', accountNumber='synthetic',
        issuer='Synthetic issuer', layoutVersion='manual-v1', yearStart=2024,
        sourceReference='Synthetic annual statement', regime='AMIT', revision=1,
        isReviewed=True, isVoided=False, components=components, createdAt=NOW, updatedAt=NOW, **fund_header)
    commit([write('managed_fund_statements/synthetic-fund', fund),
        write('managed_fund_statements/synthetic-fund/revisions/1', fund),
        write('investment_metadata/ledger', {'generation': 1}), publish(fund_id, fund_meta)])
    sale = dict(fact, transactionType='SELL', tradeDate='2025-06-01T00:00:00Z', tradeDateIso='2025-06-01')
    commit([write('investment_transactions/sale', sale)] +
        [write(f'investment_transactions/buy-{index}', fact) for index in range(12)], admin=True)
    allocation_rows = [dict(kind='allocation', payload=dict(buyTransactionId=f'buy-{index}',
        units='1', buyRevision=1, saleRevision=1)) for index in range(12)]
    allocation_id, allocation_meta, allocation_header = stage('allocation', 'sale', allocation_rows,
        generation=1, ticker='SYN', account='synthetic', sale_revision=1)
    allocation = dict(schemaVersion=2, userId='owner', sellTransactionId='sale', method='specific',
        revision=1, updatedAt=NOW, **allocation_header)
    allocation_writes = [write('investment_allocations/sale', allocation),
        write('investment_allocations/sale/revisions/1', allocation),
        write('investment_metadata/ledger', {'generation': 2}), publish(allocation_id, allocation_meta)]
    commit(allocation_writes)
    # A staged allocation cannot publish after its financial source generation changes.
    stale_id, stale_meta, stale_header = stage('allocation', 'sale', allocation_rows,
        generation=2, revision=2, ticker='SYN', account='synthetic', sale_revision=1)
    commit([write('investment_metadata/ledger', {'generation': 3})], admin=True)
    stale = dict(allocation, revision=2, **stale_header)
    commit([write('investment_allocations/sale', stale),
        write('investment_allocations/sale/revisions/2', stale),
        write('investment_metadata/ledger', {'generation': 4}), publish(stale_id, stale_meta)], expected=403)
    # Each staged allocation checks acquisition type, identity and exact revision.
    hostile = copy.deepcopy(allocation_rows)
    hostile[0]['payload']['buyRevision'] = 999
    hostile_meta = dict(stale_meta, generation=3, hash=digest(hostile), state='staging')
    hostile_id = digest(hostile_meta)
    commit([write('revision_details/' + hostile_id, hostile_meta)])
    commit([write(f'revision_details/{hostile_id}/records/0', dict(hostile[0], index=0))], expected=403)
    coverage = dict(schemaVersion=1, userId='owner', taxYearStart=2024,
        account='Synthetic broker', ticker='SYN', family='fundAnnual', state='missing',
        required=True, evidenceReference='', sourceHash='', firstPage=None, lastPage=None,
        linkedDomain='', linkedRecordId='', unitsExact='', observationDateIso='',
        revision=1, isVoided=False, createdAt=NOW, updatedAt=NOW)
    coverage_writes = [write('document_coverage/synthetic', coverage),
        write('document_coverage/synthetic/revisions/1', coverage),
        write('tax_workspace_metadata/current', {'generation': 2})]
    commit(coverage_writes, uid='other', expected=403)
    commit([write('document_coverage/synthetic', coverage)], expected=403)
    commit(coverage_writes)
    commit([write('document_coverage/synthetic/revisions/1', coverage)], expected=403)
    event = dict(schemaVersion=1, type='split', userId='owner', date='2025-02-01',
        parcelId='buy', oldUnits='10', newUnits='20', evidenceReference='Synthetic split',
        revision=1, reviewed=True, isVoided=False, createdAt=NOW, updatedAt=NOW)
    event_writes = [write('investment_events/synthetic', event),
        write('investment_events/synthetic/revisions/1', event),
        write('investment_metadata/ledger', {'generation': 4})]
    commit([write('investment_events/synthetic', event)], expected=403)
    commit(event_writes)
    commit([write('investment_events/synthetic/revisions/1', event)], expected=403)
    backup_hash = 'c' * 64
    recovery = dict(schemaVersion=1, userId='owner', backupHash=backup_hash, recordCount=1, createdAt=NOW)
    commit([write('account_restores/' + backup_hash, recovery)])
    evidence = dict(schemaVersion=1, userId='owner', path='investment_events/synthetic',
        payload=event, recordHash='d' * 64)
    evidence_path = f'account_restores/{backup_hash}/records/' + 'e' * 64
    commit([write(evidence_path, dict(evidence, path='private_profile/secrets'))], expected=403)
    commit([write(evidence_path, evidence)])
    commit([write(evidence_path, evidence)], expected=403)
    request('GET', f'/v1/{BASE}/users/owner/{evidence_path}', uid='other', expected=403)
    print('PASS: schema-2 twelve-period/twelve-adjustment/twelve-parcel publication, >1MB chunked archive, stale generation, immutable rows, owner isolation and hostile typed rows')
    print('PASS: document inventory, split events and recovery evidence require owner, typed revisions and immutable history')


if __name__ == '__main__':
    main()
