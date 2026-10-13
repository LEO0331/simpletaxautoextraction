"""Verify real emulator rules using synthetic fixtures and Python stdlib only.

Start a Firestore emulator on 127.0.0.1:8186, then run this file. No production
project, credentials, private PDFs, Firebase SDK or application dependency used.
"""
import base64
import copy
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

HOST = 'http://127.0.0.1:8186'
PROJECT = 'demo-phase1'
BASE = f'projects/{PROJECT}/databases/(default)/documents'
NOW = '2025-01-01T00:00:00Z'


def jwt(uid):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=')
    return encode({'alg': 'none', 'typ': 'JWT'}) + '.' + encode({
        'sub': uid, 'user_id': uid, 'aud': PROJECT,
        'iss': f'https://securetoken.google.com/{PROJECT}',
        'iat': int(time.time()), 'exp': int(time.time()) + 3600,
        'firebase': {'sign_in_provider': 'custom'},
    }) + '.'


def request(method, path, body=None, uid='owner', expected=200, admin=False):
    headers = {'Content-Type': 'application/json'}
    if admin:
        headers['Authorization'] = 'Bearer owner'  # Local emulator fixture seeding only.
    elif uid is not None:
        headers['Authorization'] = 'Bearer ' + jwt(uid)
    req = urllib.request.Request(HOST + path,
        data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            status, content = response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        status, content = error.code, error.read().decode()
    assert status == expected, f'{method} {path}: expected {expected}, got {status}: {content}'
    return json.loads(content) if content else {}


def value(raw):
    if raw is None:
        return {'nullValue': None}
    if isinstance(raw, bool):
        return {'booleanValue': raw}
    if isinstance(raw, int):
        return {'integerValue': str(raw)}
    if isinstance(raw, float):
        return {'doubleValue': raw}
    if isinstance(raw, str):
        return {'stringValue': raw}
    if isinstance(raw, list):
        return {'arrayValue': {'values': [value(item) for item in raw]}}
    return {'mapValue': {'fields': fields(raw)}}


def fields(data):
    return {key: {'timestampValue': raw} if key in {'tradeDate', 'createdAt', 'updatedAt'} else value(raw)
            for key, raw in data.items()}


def write(path, data):
    return {'update': {'name': BASE + '/users/owner/' + path, 'fields': fields(data)}}


def commit(writes, **options):
    return request('POST', f'/v1/{BASE}:commit', {'writes': writes}, **options)


def main():
    for attempt in range(30):
        try:
            urllib.request.urlopen(HOST, timeout=1).close()
            break
        except urllib.error.HTTPError:
            break  # A response means the local HTTP server is listening.
        except urllib.error.URLError:
            if attempt == 29:
                raise
            time.sleep(1)
    rules = (Path(__file__).resolve().parents[1] / 'firestore.rules').read_text(encoding='utf-8-sig')
    request('PUT', f'/emulator/v1/projects/{PROJECT}:securityRules',
            {'rules': {'files': [{'content': rules}]}}, uid=None)
    request('DELETE', f'/emulator/v1/{BASE}', uid=None)
    empty_report = {'schemaVersion': 1, 'userId': 'owner', 'createdAt': NOW,
        'ledgerGeneration': 0, 'inputRevisions': {}, 'openingLossEvidence': 'Synthetic verified zero activity',
        'snapshot': {'context': {'completeHistory': True, 'priorLossesReviewed': True}}}
    commit([write('investment_calculation_snapshots/empty-year', empty_report)])
    empty_report['openingLossEvidence'] = ''
    commit([write('investment_calculation_snapshots/unverified-empty-year', empty_report)], expected=403)
    fact = {'userId': 'owner', 'ticker': 'SYN', 'securityName': 'Synthetic',
            'transactionType': 'BUY', 'tradeDate': NOW, 'tradeDateIso': '2025-01-01', 'settlementDate': None,
            'units': 10, 'averagePrice': 10, 'consideration': 100,
            'brokerage': 1, 'gst': None, 'totalCost': 101,
            'confirmationNumber': None, 'accountNumber': None,
            'sourceFileName': None, 'sourceParser': 'Synthetic broker',
            'parserVersion': 'v2', 'notes': '', 'isLocked': False,
            'schemaVersion': 2, 'isVoided': False, 'isReviewed': True, 'unitsExact': '10',
            'considerationExact': '100', 'brokerageExact': '1', 'totalCostExact': '101',
            'revision': 1, 'sourceIdentity': 'a' * 64,
            'createdAt': NOW, 'updatedAt': NOW}
    def fact_writes(data, generation):
        return [write('investment_transactions/buy', data),
                write(f'investment_transactions/buy/revisions/{data["revision"]}', data),
                write('investment_metadata/ledger', {'generation': generation})]
    commit(fact_writes(fact, 1))
    commit(fact_writes(fact, 2), uid='other', expected=403)
    commit(fact_writes(fact, 2), uid=None, expected=403)
    request('GET', f'/v1/{BASE}/users/owner/investment_transactions/buy')
    request('GET', f'/v1/{BASE}/users/owner/investment_transactions/buy', uid='other', expected=403)
    request('GET', f'/v1/{BASE}/users/owner/investment_transactions/buy', uid=None, expected=403)
    commit([write('investment_transactions/buy/revisions/1', fact)], expected=403)
    invalid = copy.deepcopy(fact)
    invalid.update(revision=2, units=-1)
    commit(fact_writes(invalid, 2), expected=403)
    invalid = copy.deepcopy(fact)
    invalid.update(revision=2, unknownField='rejected')
    commit(fact_writes(invalid, 2), expected=403)
    invalid = copy.deepcopy(fact)
    invalid.update(revision=2, unitsExact='invalid')
    commit(fact_writes(invalid, 2), expected=403)
    locked = copy.deepcopy(fact)
    locked.update(revision=2, isLocked=True)
    commit(fact_writes(locked, 2))
    correction = copy.deepcopy(locked)
    correction.update(revision=3, units=20, isLocked=False)
    commit(fact_writes(correction, 3), expected=403)
    unlocked = copy.deepcopy(locked)
    unlocked.update(revision=3, isLocked=False)
    commit(fact_writes(unlocked, 3))
    commit(fact_writes(unlocked, 4), expected=403)
    correction.update(revision=4)
    commit([write('investment_transactions/buy', correction),
            write('investment_metadata/ledger', {'generation': 4})], expected=403)
    commit([{'delete': BASE + '/users/owner/investment_transactions/buy'}], expected=403)
    snapshot = {'userId': 'owner', 'createdAt': NOW, 'ledgerGeneration': 3,
                'inputRevisions': {'buy': 3}, 'calculationVersion': 'synthetic-test'}
    commit([write('investment_calculation_snapshots/report', snapshot)])
    commit([write('investment_calculation_snapshots/report', snapshot)], expected=403)
    snapshot['ledgerGeneration'] = 2
    commit([write('investment_calculation_snapshots/stale', snapshot)], expected=403)
    sale = copy.deepcopy(fact)
    sale.update(transactionType='SELL', tradeDate='2025-06-01T00:00:00Z', tradeDateIso='2025-06-01', totalCost=99, totalCostExact='99')
    commit([write('investment_transactions/sell', sale),
            write('investment_transactions/sell/revisions/1', sale),
            write('investment_metadata/ledger', {'generation': 4})])
    allocation = {'userId': 'owner', 'sellTransactionId': 'sell', 'method': 'specific',
                  'selections': [{'buyTransactionId': 'buy', 'units': '10'}],
                  'transactionRevisions': {'buy': 3, 'sell': 1}, 'revision': 1, 'updatedAt': NOW}
    allocation_writes = [write('investment_allocations/sell', allocation),
                         write('investment_allocations/sell/revisions/1', allocation),
                         write('investment_metadata/ledger', {'generation': 5})]
    commit(allocation_writes)
    commit(allocation_writes, expected=403)
    stale_allocation = copy.deepcopy(allocation)
    stale_allocation.update(revision=2, transactionRevisions={'buy': 2, 'sell': 1})
    commit([write('investment_allocations/sell', stale_allocation),
            write('investment_allocations/sell/revisions/2', stale_allocation),
            write('investment_metadata/ledger', {'generation': 6})], expected=403)
    wrong_type = copy.deepcopy(allocation)
    wrong_type.update(revision=2, selections=[{'buyTransactionId': 'sell', 'units': '10'}])
    commit([write('investment_allocations/sell', wrong_type),
            write('investment_allocations/sell/revisions/2', wrong_type),
            write('investment_metadata/ledger', {'generation': 6})], expected=403)
    allocation['method'] = 'automatic'
    allocation['revision'] = 2
    commit([write('investment_allocations/sell', allocation),
            write('investment_allocations/sell/revisions/2', allocation),
            write('investment_metadata/ledger', {'generation': 6})], expected=403)
    boundary_writes = []
    for index in range(4):
        buy = copy.deepcopy(fact)
        buy.update(units=1, unitsExact='1', consideration=10, considerationExact='10',
                   brokerage=0, brokerageExact='0', totalCost=10, totalCostExact='10',
                   confirmationNumber=f'synthetic-boundary-{index}')
        boundary_writes.extend([write(f'investment_transactions/boundary-{index}', buy),
                           write(f'investment_transactions/boundary-{index}/revisions/1', buy)])
    boundary_writes.append(write('investment_metadata/ledger', {'generation': 6}))
    commit(boundary_writes)
    boundary_sale = copy.deepcopy(sale)
    boundary_sale.update(units=4, unitsExact='4', consideration=44, considerationExact='44',
                    brokerage=0, brokerageExact='0', totalCost=44, totalCostExact='44')
    commit([write('investment_transactions/boundary-sale', boundary_sale),
            write('investment_transactions/boundary-sale/revisions/1', boundary_sale),
            write('investment_metadata/ledger', {'generation': 7})])
    boundary_allocation = copy.deepcopy(allocation)
    boundary_allocation.update(sellTransactionId='boundary-sale', revision=1, method='specific',
        selections=[{'buyTransactionId': f'boundary-{index}', 'units': '1'} for index in range(4)],
        transactionRevisions={'boundary-sale': 1, **{f'boundary-{index}': 1 for index in range(4)}})
    commit([write('investment_allocations/boundary-sale', boundary_allocation),
            write('investment_allocations/boundary-sale/revisions/1', boundary_allocation),
            write('investment_metadata/ledger', {'generation': 8})])
    overflow_allocation = copy.deepcopy(boundary_allocation)
    overflow_allocation['revision'] = 2
    overflow_allocation['selections'].append({'buyTransactionId': 'buy', 'units': '1'})
    commit([write('investment_allocations/boundary-sale', overflow_allocation),
            write('investment_allocations/boundary-sale/revisions/2', overflow_allocation),
            write('investment_metadata/ledger', {'generation': 9})], expected=403)
    legacy = copy.deepcopy(fact)
    for key in ['revision', 'sourceIdentity', 'isReviewed', 'schemaVersion', 'tradeDateIso',
                'unitsExact', 'considerationExact', 'brokerageExact', 'totalCostExact']:
        legacy.pop(key, None)
    request('PATCH', f'/v1/{BASE}/users/owner/investment_transactions/legacy',
            {'fields': fields(legacy)}, admin=True)
    upgraded = copy.deepcopy(fact)
    upgraded['notes'] = 'Synthetic explicit legacy review'
    upgrade_writes = [write('investment_transactions/legacy', upgraded),
                      write('investment_transactions/legacy/revisions/1', upgraded),
                      write('investment_metadata/ledger', {'generation': 9})]
    commit(upgrade_writes, expected=403)
    commit([*upgrade_writes, write('investment_transactions/legacy/revisions/0', legacy)])
    commit([write('investment_transactions/legacy/revisions/0', upgraded)], expected=403)
    fund = {'schemaVersion': 1, 'userId': 'owner', 'ticker': 'SYN',
        'accountNumber': 'synthetic-account', 'issuer': 'Synthetic issuer',
        'layoutVersion': 'annual-v1', 'yearStart': 2024, 'sourceReference': 'Synthetic statement',
        'regime': 'AMIT', 'revision': 1, 'isReviewed': True, 'isVoided': False,
        'components': {'australianIncome': '100', 'grossCapitalGain': '0'},
        'adjustments': [], 'drpLinks': [], 'createdAt': NOW, 'updatedAt': NOW}
    def fund_writes(data, generation):
        return [write('managed_fund_statements/synthetic', data),
            write(f'managed_fund_statements/synthetic/revisions/{data["revision"]}', data),
            write('investment_metadata/ledger', {'generation': generation})]
    commit(fund_writes(fund, 10))
    request('GET', f'/v1/{BASE}/users/owner/managed_fund_statements/synthetic')
    request('GET', f'/v1/{BASE}/users/owner/managed_fund_statements/synthetic', uid='other', expected=403)
    request('GET', f'/v1/{BASE}/users/owner/managed_fund_statements/synthetic', uid=None, expected=403)
    corrected = copy.deepcopy(fund)
    corrected.update(revision=2, sourceReference='Synthetic corrected statement')
    commit(fund_writes(corrected, 11), uid='other', expected=403)
    commit(fund_writes(corrected, 11), uid=None, expected=403)
    invalid = copy.deepcopy(corrected)
    invalid['privatePdfBytes'] = 'not permitted'
    commit(fund_writes(invalid, 11), expected=403)
    invalid = copy.deepcopy(corrected)
    invalid['components']['unexpected'] = '1'
    commit(fund_writes(invalid, 11), expected=403)
    invalid = copy.deepcopy(corrected)
    invalid['components']['australianIncome'] = 'NaN'
    commit(fund_writes(invalid, 11), expected=403)
    invalid = copy.deepcopy(corrected)
    invalid['adjustments'] = [{'parcelId': 'buy', 'amount': '-5', 'date': '2025-06-30',
        'evidenceReference': 'Synthetic allocation', 'units': '1', 'beforeSaleId': None,
        'unknown': 'rejected'}]
    commit(fund_writes(invalid, 11), expected=403)
    commit([write('managed_fund_statements/synthetic', corrected),
        write('investment_metadata/ledger', {'generation': 11})], expected=403)
    commit(fund_writes(corrected, 11))
    commit(fund_writes(corrected, 12), expected=403)
    commit([write('managed_fund_statements/synthetic/revisions/1', corrected)], expected=403)
    commit([{'delete': BASE + '/users/owner/managed_fund_statements/synthetic'}], expected=403)
    corrected.update(revision=3, isVoided=True)
    commit(fund_writes(corrected, 12))
    boundary_fund = copy.deepcopy(corrected)
    boundary_fund.update(revision=4, isVoided=False)
    boundary_fund['components'] = {key: '0' for key in ['australianIncome', 'foreignIncome',
        'frankingCredits', 'foreignTaxOffset', 'withholding', 'cashDistributions',
        'discountedCapitalGain', 'otherCapitalGain', 'grossCapitalGain', 'amitShortfall', 'amitExcess']}
    boundary_fund['adjustments'] = [{'parcelId': f'boundary-{i}', 'amount': '1',
        'date': '2025-06-30', 'evidenceReference': 'Synthetic allocation',
        'beforeSaleId': None, 'units': '1'} for i in range(4)]
    boundary_fund['drpLinks'] = [{'buyTransactionId': f'boundary-{i}',
        'cashEntitlement': '1', 'reinvestedAmount': '1', 'residualCash': '0',
        'evidenceReference': 'Synthetic DRP'} for i in range(4)]
    commit(fund_writes(boundary_fund, 13))
    too_many = copy.deepcopy(boundary_fund)
    too_many['revision'] = 5
    too_many['adjustments'].append(copy.deepcopy(too_many['adjustments'][0]))
    commit(fund_writes(too_many, 14), expected=403)
    too_many = copy.deepcopy(boundary_fund)
    too_many['revision'] = 5
    too_many['drpLinks'].append(copy.deepcopy(too_many['drpLinks'][0]))
    commit(fund_writes(too_many, 14), expected=403)
    malformed_drp = copy.deepcopy(boundary_fund)
    malformed_drp['revision'] = 5
    malformed_drp['drpLinks'][0]['cashEntitlement'] = 'NaN'
    commit(fund_writes(malformed_drp, 14), expected=403)
    malformed_drp['drpLinks'][0]['cashEntitlement'] = 1
    commit(fund_writes(malformed_drp, 14), expected=403)
    malformed_amount = copy.deepcopy(boundary_fund)
    malformed_amount['revision'] = 5
    malformed_amount['components']['australianIncome'] = 1
    commit(fund_writes(malformed_amount, 14), expected=403)
    malformed_amount['components']['australianIncome'] = '1|1'
    commit(fund_writes(malformed_amount, 14), expected=403)
    created_boundary = copy.deepcopy(boundary_fund)
    created_boundary['revision'] = 1
    commit([write('managed_fund_statements/boundary-create', created_boundary),
        write('managed_fund_statements/boundary-create/revisions/1', created_boundary),
        write('investment_metadata/ledger', {'generation': 14})])
    print('PASS: managed fund ownership, typed schema, correction history, generation and immutable voids')
    print('PASS: real Firestore emulator ownership, schema, locks, revisions, generation, immutable snapshots and 4-parcel allocation boundary')


if __name__ == '__main__':
    main()
