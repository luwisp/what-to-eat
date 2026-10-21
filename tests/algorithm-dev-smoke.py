#!/usr/bin/env python3
"""Real SQLite -> Cangjie -> HTTP interactive-workbench scenarios (no browser)."""
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def person(id, **changes):
    preferences = dict(allergens=[], avoidFoods=[], dietMode='none', maxSpiceLevel=None,
                       tastePreferences=[], wantedDishIds=[], wantedSetMealIds=[], note='')
    preferences.update(changes)
    return dict(id=id, nickname=id, submitted=True, preferences=preferences)


class AlgorithmDevHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1', 0))
            cls.port = reserve.getsockname()[1]
        cls.origin = f'http://127.0.0.1:{cls.port}'
        env = {**os.environ, 'JUXIAOBAO_DEV_PORT': str(cls.port), 'cjHeapSize': '64MB',
               'JUXIAOBAO_DEV_HOST': '0.0.0.0', 'JUXIAOBAO_DEV_ORIGIN': 'http://20.48.96.44:8091'}
        cls.db = Path(env.get('JUXIAOBAO_DEV_DB', str(ROOT / 'data/runtime/juxiaobao.sqlite')))
        cls.before = hashlib.sha256(cls.db.read_bytes()).hexdigest()
        cls.process = subprocess.Popen(['bash', 'scripts/cj.sh', 'exec', 'target/algorithm-dev/server'],
                                       cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if cls.process.poll() is not None:
                    raise RuntimeError('Algorithm dev server exited')
                try:
                    with urllib.request.urlopen(cls.origin + '/health', timeout=.2) as r:
                        if r.status == 200:
                            break
                except (OSError, urllib.error.URLError):
                    time.sleep(.05)
            else:
                raise RuntimeError('Algorithm dev server did not start')
            with urllib.request.urlopen(cls.origin + '/api/dev/menu') as r:
                cls.menu = json.load(r)
        except Exception:
            cls.process.terminate()
            cls.process.wait(timeout=5)
            raise

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        cls.process.wait(timeout=5)
        after = hashlib.sha256(cls.db.read_bytes()).hexdigest()
        if after != cls.before:
            raise AssertionError('Read-only experiments changed the SQLite database')

    def payload(self):
        return dict(people=4, budgetPerPersonFen=2500, members=[person(f'm{i}') for i in range(4)],
                    maxExpansions=120, width=2, unknownDishIds=[], unavailableDishIds=[])

    def post(self, body, expected=200, origin=None):
        req = urllib.request.Request(self.origin + '/api/dev/recommend',
                                     data=json.dumps(body).encode(), method='POST',
                                     headers={'Content-Type': 'application/json', 'Origin': origin or self.origin})
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                self.assertEqual(response.status, expected)
                result = json.load(response)
        except urllib.error.HTTPError as error:
            self.assertEqual(error.code, expected)
            result = json.load(error)
        if expected == 200:
            if body.get('algorithm') != 'v3':
                self.assertLessEqual(tuple(result['optimizedObjective']), tuple(result['baselineObjective']))
            self.assertLessEqual(result['expansions'], body['maxExpansions'])
        return result

    def meal_payload(self):
        body = self.payload()
        body.update(algorithm='v3', people=5, budgetPerPersonFen=4500,
                    maxExpansions=6000, width=16, menuVersion=self.menu['menuVersion'])
        body['members'] = [person('a', allergens=['花生']), person('b', maxSpiceLevel=0),
                           person('c', avoidFoods=['猪肉']), person('d'), person('e')]
        for member in body['members']:
            member['meal'] = dict(appetite='normal', stapleMode='default', stapleDishId=None,
                                  wantedIngredients=[], wantedExtraIds=[], wantedSpiceLevel=None)
        body['members'][3]['meal']['wantedSpiceLevel'] = 3
        return body

    def test_v3_real_mixed_preferences_and_budget(self):
        result = self.post(self.meal_payload())
        report = result['mealReport']
        self.assertEqual(report['status'], 'complete', report)
        self.assertEqual(report['estimatedHotNeed'], 5)
        self.assertTrue(report['targetBandReached'], report)
        self.assertLessEqual(result['optimized']['totalFen'], 22500)
        self.assertEqual(result['optimized']['uncoveredIds'], [])
        self.assertFalse(any(w['itemType'] == 'spice' for w in result['optimized']['unmetWishes']))
        self.assertTrue(all(row['stapleDishId'] for row in report['members']))
        for row in report['members']:
            self.assertGreaterEqual(row['halfDishAllocated'], row['halfDishNeed'])

    def test_v3_appetite_and_explicit_staple_optout(self):
        body = self.meal_payload()
        body['members'][0]['meal'].update(appetite='extraLarge', stapleMode='none')
        body['members'][1]['meal']['appetite'] = 'small'
        result = self.post(body)
        report = result['mealReport']
        self.assertEqual(report['estimatedHotNeed'], 6)
        self.assertTrue(report['members'][0]['stapleOptOut'])
        self.assertEqual(report['members'][0]['halfDishNeed'], 4)

    def test_v3_allows_multiple_snack_and_drink_portions(self):
        facts = {row['dishId']: row for row in self.menu['mealMetadata']}
        snack = next(d for d in self.menu['dishes'] if facts[d['id']]['role'] == 'side')
        drink = next(d for d in self.menu['dishes'] if facts[d['id']]['role'] == 'drink')
        body = self.meal_payload()
        body.update(people=1, budgetPerPersonFen=None)
        body['members'] = [person('m')]
        body['members'][0]['meal'] = dict(
            appetite='normal', stapleMode='none', stapleDishId=None, wantedIngredients=[],
            wantedExtras=[dict(dishId=snack['id'], quantity=2),
                                                dict(dishId=drink['id'], quantity=3)],
            wantedSpiceLevel=None)
        result = self.post(body)
        quantities = {item['itemId']: item['quantity'] for item in result['optimized']['items']}
        self.assertEqual(quantities[snack['id']], 2)
        self.assertEqual(quantities[drink['id']], 3)
        self.assertFalse(any(w['itemId'] in (snack['id'], drink['id'])
                             for w in result['optimized']['unmetWishes']))

    def test_v3_high_budget_vegetarian_uses_automatic_extras(self):
        body = self.meal_payload()
        body.update(people=1, budgetPerPersonFen=10000)
        body['members'] = [person('solo', dietMode='ovoLacto')]
        body['members'][0]['meal'] = dict(
            appetite='normal', stapleMode='default', stapleDishId=None,
            wantedIngredients=[], wantedExtras=[], wantedSpiceLevel=None)
        result = self.post(body)
        report = result['mealReport']
        self.assertEqual(report['status'], 'complete', report)
        self.assertTrue(report['targetBandReached'], report)
        self.assertGreaterEqual(result['optimized']['totalFen'], 9000)
        self.assertLessEqual(result['optimized']['totalFen'], 10000)
        self.assertTrue(any('自动加入适配的小吃或饮料' in n
                            for n in result['optimized']['notices']))

    def test_v3_zero_budget_and_menu_version_guard(self):
        body = self.meal_payload()
        body['budgetPerPersonFen'] = 0
        result = self.post(body)
        self.assertEqual(result['mealReport']['status'], 'noCandidate')
        self.assertEqual(result['optimized']['totalFen'], 0)
        body['menuVersion'] += 1
        self.post(body, expected=409)

    def test_v3_script_and_reviewed_metadata(self):
        self.assertEqual(len(self.menu['mealMetadata']), 84)
        self.assertNotIn('水', self.menu['ingredientOptions'])
        with urllib.request.urlopen(self.origin + '/app.js') as response:
            script = response.read().decode()
            self.assertIn('wantedSpiceLevel', script)
            self.assertIn('syncMembersToPeople', script)
            self.assertIn('同行人 ${String.fromCharCode(64+index)}', script)
            self.assertIn('dish-description', script)
            self.assertNotIn('data-field="dietMode"', script)

    def test_user_export_noodle_replacement_has_personal_staple(self):
        body = json.loads((ROOT / 'tests/fixtures/laoxiangji-noodle-request.json').read_text())
        result = self.post(body)
        report = result['mealReport']
        self.assertEqual(report['status'], 'complete', report)
        member = next(m for m in report['members'] if m['memberId'] == 'm2')
        dish = next(d for d in result['menu']['dishes'] if d['id'] == member['stapleDishId'])
        fact = next(f for f in result['menu']['mealMetadata'] if f['dishId'] == dish['id'])
        self.assertEqual(fact['stapleKind'], 'noodles')
        self.assertEqual(fact['stapleUnits'], 1)
        self.assertNotIn('熟猪油', dish['ingredients'])
        self.assertTrue(any(i['itemId'] == dish['id'] for i in result['optimized']['items']))
        print('Confirmed export regression: 同行人 A -> ' + dish['name'])

    def test_configured_public_origin_is_accepted(self):
        self.post(self.payload(), origin='http://20.48.96.44:8091')

    def test_page_menu_and_real_picture(self):
        self.assertEqual(len(self.menu['dishes']), 84)
        with urllib.request.urlopen(self.origin + '/') as response:
            page = response.read().decode()
            self.assertIn('推荐算法实验室', page)
            self.assertNotIn('严格素食', page)
        image = self.menu['dishes'][0]['imageUrl']
        with urllib.request.urlopen(self.origin + image) as response:
            self.assertTrue(response.headers['Content-Type'].startswith('image/'))
            self.assertGreater(len(response.read()), 100)

    def test_normal_deterministic_and_not_worse_than_greedy(self):
        body = self.payload()
        first = self.post(body)
        second = self.post(body)
        self.assertFalse(first['stoppedByDeadline'])
        self.assertEqual(first['optimized']['items'], second['optimized']['items'])
        self.assertEqual(first['optimized']['uncoveredIds'], [])

    def test_allergy_and_unknown_simulation_exclude_entire_table_without_persisting(self):
        body = self.payload()
        body['members'][0]['preferences']['allergens'] = ['花生']
        result = self.post(body)
        excluded = {row['dishId'] for row in result['eligibility'] if row['tableExcluded']}
        self.assertTrue(excluded)
        self.assertFalse(excluded & {d['dish']['id'] for d in result['optimized']['expandedDishes']})
        body['unknownDishIds'] = [d['id'] for d in self.menu['dishes']]
        simulated = self.post(body)
        self.assertEqual(len(simulated['optimized']['uncoveredIds']), 4)
        self.assertEqual(simulated['optimized']['items'], [])
        with urllib.request.urlopen(self.origin + '/api/dev/menu') as response:
            self.assertEqual(json.load(response), self.menu)

    def test_plant_member_gets_two_distinct_appropriate_dishes(self):
        body = self.payload()
        body['members'][1]['preferences']['dietMode'] = 'plant'
        result = self.post(body)
        fit_ids = {r['dishId'] for r in result['eligibility']
                   if any(f['memberId'] == 'm1' and f['status'] == 'fit' for f in r['fits'])}
        selected = {d['dish']['id'] for d in result['optimized']['expandedDishes'] if d['dish']['category'] in ('hot', 'cold')}
        self.assertGreaterEqual(len(fit_ids & selected), 2)

    def test_unsubmitted_allergy_is_not_treated_as_a_submitted_constraint(self):
        body = self.payload()
        body['members'][0]['submitted'] = False
        body['members'][0]['preferences']['allergens'] = ['花生']
        body['unknownDishIds'] = [d['id'] for d in self.menu['dishes']]
        result = self.post(body)
        self.assertFalse(any(row['tableExcluded'] for row in result['eligibility']))
        self.assertTrue(all(f['memberId'] != 'm0' for row in result['eligibility'] for f in row['fits']))

    def test_conflicting_wish_stays_unmet_and_low_budget_is_reported(self):
        body = self.payload()
        spicy = next(d for d in self.menu['dishes'] if d['name'] == '香辣鸡杂')
        prefs = body['members'][0]['preferences']
        prefs.update(maxSpiceLevel=0, wantedDishIds=[spicy['id']])
        result = self.post(body)
        self.assertTrue(any(w['memberId'] == 'm0' and w['itemId'] == spicy['id'] for w in result['optimized']['unmetWishes']))
        body['budgetPerPersonFen'] = 1
        low = self.post(body)
        self.assertTrue(low['optimized']['budgetWarning'])

    def test_all_unavailable_returns_explicit_partial_result(self):
        body = self.payload()
        body['unavailableDishIds'] = [d['id'] for d in self.menu['dishes']]
        result = self.post(body)
        self.assertEqual(len(result['optimized']['uncoveredIds']), 4)
        self.assertEqual(result['optimized']['items'], [])

    def test_invalid_input_no_submission_and_cross_site_are_rejected(self):
        body = self.payload()
        body['people'] = 0
        self.post(body, 400)
        body = self.payload()
        for m in body['members']:
            m['submitted'] = False
        self.assertEqual(self.post(body, 400)['error']['code'], 'NO_SUBMISSIONS')
        self.post(self.payload(), 403, origin='https://unrelated.test')


if __name__ == '__main__':
    unittest.main(verbosity=2)
