SELECT
    C1.name as card_1,
    C2.name as card_2,
count(*) as cnt
FROM decklists D1
INNER JOIN decklists D2 on D1.deck_id = D2.deck_id
INNER JOIN decks D on D.id = D1.deck_id
INNER JOIN cards C1 on C1.scryfall_id = D1.scryfall_id  -- Cards being counted 2x since (A1,A2) != (A2,A1)
INNER JOIN cards C2 on C2.scryfall_id = D2.scryfall_id
WHERE D1.scryfall_id != D2.scryfall_id
    AND C1.name NOT IN ('Plains', 'Island', 'Swamp', 'Mountain', 'Forest')
    AND C2.name NOT IN ('Plains', 'Island', 'Swamp', 'Mountain', 'Forest')
    -- AND D.cubecobra_id = '3f05b561-c5f0-40fd-a67c-76fe14905b1c'
    -- AND D.set_id = 'tdm'
GROUP BY C1.name, C2.name
HAVING cnt > 1
ORDER BY cnt DESC