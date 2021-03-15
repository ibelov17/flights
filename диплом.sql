1) В каких городах больше одного аэропорта? 
 
Беру таблицу airports (аэропорты) 
Группирую по столбцу city (город) 
Считаю кол-во аэропортов в городе 
Отсекаю города где 1 аэропорт 
Упорядочиваю по убыванию 

select city, count(airport_code) as number_of_airports
from bookings.airports
group by city
having count(airport_code) > 1
order by number_of_airports desc 

-------------------------------------------------------------
2) В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета? 
 
Беру представление flights_v 
Вывожу строки, где код самолета соответствует коду из подзапроса 
	подзапрос 
	Беру таблицу самолеты 
	упорядочиваю по убыванию максимальной дальности полета, км 
	оставляю только 1 позицию  
Вывожу уникальные названия аэропортов отправления (аэропорты прибытия такие же, т.к. рейсы летают туда-обратно) 

select distinct departure_airport_name as airports
from bookings.flights_v fv 
where aircraft_code = (
	select aircraft_code 
	from bookings.aircrafts a
	order by "range" desc 
	limit 1)
	
---------------------------------------------------------------------
3) Вывести 10 рейсов с максимальным временем задержки вылета 
 
Задержка вылета - это разность фактического времени вылета и время вылета по расписанию
В расчет берем только рейсы уже вылетевшие, поэтому оставляем только строки где фактическое время вылета notnull
Упорядочить по убыванию 
Отобрать 10 первых LIMIT 

select flight_id , scheduled_departure , actual_departure, (actual_departure - scheduled_departure) as delayed_time
from bookings.flights_v fv 
where actual_departure notnull
order by delayed_time desc 
limit 10

--------------------------------------------------------------------------
4) Были ли брони, по которым не были получены посадочные талоны? 
 
Бронь состоит из билетов
При регистрации на рейс предъявляется билет и выдается посадочный талон с номером (boarding_no)
Значит ответом на вопрос заказчика будут строки где Номер посадочного талона (boarding_no) = null 

select t.book_ref , t.ticket_no, bp.boarding_no 
from tickets t
left join boarding_passes bp on t.ticket_no = bp.ticket_no 
where bp.boarding_no is null
order by book_ref desc 

-------------------------------------------------------------------------------
5) Найдите свободные места для каждого рейса, их % отношение к общему количеству мест в самолете. 
Добавьте столбец с накопительным итогом - суммарное количество вывезенных пассажиров из аэропорта за день. 
Т.е. в этом столбце должна отражаться сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах за сегодняшний день 
 
Из таблицы ticket_flights нахожу кол-во занятых мест на каждом рейсе (по кол-ву билетов)
Из таблицы seats нахожу общее кол-во мест в каждом самолете
Вычитая кол-во занятых мест из общего кол-ва мест в самолете нахожу кол-во пустых мест
Поделив пустые места на все места в самолете *100 узнаю % свободных мест
Столбец с накопительным итогом считаю через оконную функцию по аэропорту и дате вылета

select f.flight_id , f.departure_airport ,f.scheduled_departure , f.aircraft_code, (alls.all_seats - op.occupied_places) as empty_seats,
		((alls.all_seats - op.occupied_places) * 100 / alls.all_seats) as percent_empty_seats,
		sum(op.occupied_places) over (partition by f.departure_airport, date(f.scheduled_departure) order by f.scheduled_departure)
from flights f
left join (
	select flight_id , count(ticket_no) as occupied_places
	from ticket_flights tf 
	group by flight_id) as op on f.flight_id = op.flight_id 
left join (
	select aircraft_code , count(seat_no) as all_seats
	from seats s 
	group  by aircraft_code) as alls on f.aircraft_code = alls.aircraft_code
order by f.flight_id 

----------------------------------------------------------------------------------------------
6) Найдите процентное соотношение перелетов по типам самолетов от общего количества. 
 
Сначала считаю кол-во перелетов на каждом самолете
Потом вычисляю общее кол-во перелетов
Делю одно на другое, привожу к numeric для функции round, умножаю на 100 - получаются проценты

select aircraft_code , flights , all_flights , round(flights / all_flights::numeric, 3)*100 as percent
from (
	select aircraft_code , 
		count(flight_id) as flights,
		(select count(flight_id) from flights f) as all_flights
	from flights
	group by aircraft_code ) as af
order by round(flights / all_flights::numeric, 3) desc 

-----------------------------------------------------------------------------------------------
7) Были ли города, в которые можно добраться бизнес-классом дешевле, чем эконом-классом в рамках перелета? 
 
CTE #1 -- ищу минимальную стоимость перелета бизнес-классом 
CTE #2 -- ищу максимальную стоимость перелета эконом-классом
Беру представление flight_v (тк в нем сразу есть flight_id и название города прибытия), по flight_id присоединяю две таблицы из CTE
В общей таблице сравниваю для каждого перелета стоимость билетов эконом и бизнес классов
Вывожу столбец с условием - все значение null - значит таких городов нет (бизнес всегда дороже эконома)

with mb as ( -- ищу минимальную стоимость перелета бизнес-классом
	select flight_id, min(amount) as min_bis 
	from ticket_flights tf 
	where fare_conditions = 'Business'
	group by flight_id 
	order by flight_id),
me as ( -- ищу максимальную стоимость перелета эконом-классом
	select flight_id, max(amount) as max_eco
	from ticket_flights tf 
	where fare_conditions = 'Economy'
	group by flight_id 
	order by flight_id)
select fv.flight_id , fv.arrival_city
from flights_v fv
left join mb on fv.flight_id = mb.flight_id
left join me on fv.flight_id = me.flight_id
where min_bis < max_eco
	
-------------------------------------------------------------------------------------------
8) Между какими городами нет прямых рейсов? 
- Декартово произведение в предложении FROM 
- Представления 
- Оператор EXCEPT 

-- создал представление со всеми городами (назвал города вылета)
create view belov_departure_city as 
	select distinct (city ->> 'ru') as departure_city 
	from airports_data

-- создал представление со всеми городами (назвал города прилета)
create view belov_arrival_city as 
	select distinct (city ->> 'ru') as arrival_city 
	from airports_data

--с помощью декартова произведения всех городов нахожу все возможные перелеты
create view belov_all_flights as
	select *
	from belov_departure_city , belov_arrival_city 
	where belov_departure_city.departure_city != belov_arrival_city.arrival_city

-- с помощью оператора except из множетсва всех возможных перелетов между городами убираю все реальные перелеты и получаю все города между которыми нет прямых рейсов
select *
from belov_all_flights
except
select departure_city , arrival_city 
from flights_v fv 

----------------------------------------------------------------------------------------
9) Вычислите расстояние между аэропортами, связанными прямыми рейсами,
сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы * 
 
Из таблицы flights делю столбец с координатами на широту и долготу для удобства восприятия формулы
Затем считаю расстояние между аэропортами и добавляю столбец с дальность полета самолета
Добавлю столбец с условием - все самолеты соответствуют длине рейса, который они обслуживают

with r as ( -- ищу и удаляю дубликаты пар аэропортов
	select departure_airport , arrival_airport, aircraft_code
	from routes r 
	group by departure_airport , arrival_airport, aircraft_code)
select departure_airport, arrival_airport, between_airports, "range",
	(case
		when between_airports < "range" then 'corresponds'
	end) 
from (
	select departure_airport, arrival_airport, 
		acos(sind(latitude_a)*sind(latitude_b) + cosd(latitude_a)*cosd(latitude_b)*cosd(longitude_a - longitude_b))*6371 as between_airports,
		"range"
	from (
		select r.departure_airport , ad.coordinates[0] as longitude_a, ad.coordinates [1] as latitude_a ,
				r.arrival_airport, ad2.coordinates [0] as longitude_b, ad2.coordinates [1] as latitude_b ,  ad3."range"
		from r 
		left join airports_data ad on r.departure_airport = ad.airport_code
		left join airports_data ad2 on r.arrival_airport = ad2.airport_code
		left join aircrafts_data ad3 on r.aircraft_code = ad3.aircraft_code 
		) as coor
	) as r