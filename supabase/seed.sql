-- =====================================================================
-- SEED · Datos iniciales
-- Empresa demo, 20 tiendas, parámetros legales, conceptos y feriados
-- =====================================================================

-- ---------------------------------------------------------------------
-- EMPRESA
-- ---------------------------------------------------------------------
insert into empresas (id, nombre, razon_social, rif, direccion_fiscal, telefono, email,
                      dias_utilidades, tolerancia_retardo_min)
values ('11111111-1111-1111-1111-111111111111',
        'Moda Nacional',
        'INVERSIONES MODA NACIONAL, C.A.',
        'J-40123456-7',
        'Av. Francisco de Miranda, Torre Delta, Piso 8, Chacao, Caracas, Distrito Capital',
        '+58 212-555-0100', 'rrhh@modanacional.com.ve',
        30, 10);

-- ---------------------------------------------------------------------
-- 20 TIENDAS
-- ---------------------------------------------------------------------
insert into tiendas (empresa_id, codigo, nombre, estado_pais, ciudad, centro_costo) values
('11111111-1111-1111-1111-111111111111','T001','Sambil Chacao',        'Distrito Capital','Caracas','CC-001'),
('11111111-1111-1111-1111-111111111111','T002','CCCT',                 'Distrito Capital','Caracas','CC-002'),
('11111111-1111-1111-1111-111111111111','T003','Líder Sabana Grande',  'Distrito Capital','Caracas','CC-003'),
('11111111-1111-1111-1111-111111111111','T004','Millennium Los Dos Caminos','Miranda','Caracas','CC-004'),
('11111111-1111-1111-1111-111111111111','T005','Paseo El Hatillo',     'Miranda','El Hatillo','CC-005'),
('11111111-1111-1111-1111-111111111111','T006','Sambil Valencia',      'Carabobo','Valencia','CC-006'),
('11111111-1111-1111-1111-111111111111','T007','Metrópolis Valencia',  'Carabobo','Valencia','CC-007'),
('11111111-1111-1111-1111-111111111111','T008','Sambil Maracaibo',     'Zulia','Maracaibo','CC-008'),
('11111111-1111-1111-1111-111111111111','T009','Galerías Maracaibo',   'Zulia','Maracaibo','CC-009'),
('11111111-1111-1111-1111-111111111111','T010','Sambil Barquisimeto',  'Lara','Barquisimeto','CC-010'),
('11111111-1111-1111-1111-111111111111','T011','Trinitarias Barquisimeto','Lara','Barquisimeto','CC-011'),
('11111111-1111-1111-1111-111111111111','T012','Sambil Maracay',       'Aragua','Maracay','CC-012'),
('11111111-1111-1111-1111-111111111111','T013','Parque Costazul',      'Anzoátegui','Lechería','CC-013'),
('11111111-1111-1111-1111-111111111111','T014','Regina Puerto La Cruz','Anzoátegui','Puerto La Cruz','CC-014'),
('11111111-1111-1111-1111-111111111111','T015','Orinokia Puerto Ordaz','Bolívar','Ciudad Guayana','CC-015'),
('11111111-1111-1111-1111-111111111111','T016','Ciudad Alta Vista',    'Bolívar','Ciudad Guayana','CC-016'),
('11111111-1111-1111-1111-111111111111','T017','Sambil San Cristóbal', 'Táchira','San Cristóbal','CC-017'),
('11111111-1111-1111-1111-111111111111','T018','Viva Mérida',          'Mérida','Mérida','CC-018'),
('11111111-1111-1111-1111-111111111111','T019','Sambil Margarita',     'Nueva Esparta','Porlamar','CC-019'),
('11111111-1111-1111-1111-111111111111','T020','Costa Azul Margarita', 'Nueva Esparta','Porlamar','CC-020');

-- ---------------------------------------------------------------------
-- PARÁMETROS LEGALES
-- ⚠️ Verificar cada valor contra Gaceta Oficial antes de producción.
-- ---------------------------------------------------------------------
insert into parametros_legales (clave, descripcion, valor, moneda, unidad, vigente_desde, gaceta_oficial, fundamento) values
-- Montos base
('SALARIO_MINIMO','Salario mínimo nacional mensual',130.00,'VES','monto','2022-03-15','G.O. 6.691 Ext.','Decreto 4.653'),
('CESTATICKET','Cestaticket socialista mensual',40.00,'USD','monto','2026-01-01','Por confirmar','Ley de Alimentación para los Trabajadores'),
('BONO_GUERRA','Bonificación de guerra económica (no salarial)',160.00,'USD','monto','2026-05-01','Por confirmar','Art. 105 LOTTT - sin incidencia salarial'),
('INGRESO_MINIMO_INTEGRAL','Ingreso mínimo integral de referencia',240.00,'USD','monto','2026-05-01','Anuncio ministerial','Referencia de política salarial'),
('UNIDAD_TRIBUTARIA','Valor de la Unidad Tributaria',43.00,'VES','monto','2025-06-02','G.O. 43.140','Providencia SNAT/2025/000048'),

-- Alícuotas de seguridad social (trabajador)
('IVSS_TRABAJADOR','Retención IVSS al trabajador',0.04,null,'porcentaje','2012-05-07','','Ley del Seguro Social art. 62'),
('RPE_TRABAJADOR','Retención Régimen Prestacional de Empleo',0.005,null,'porcentaje','2012-05-07','','LRPE art. 46'),
('FAOV_TRABAJADOR','Retención FAOV (Ley de Política Habitacional)',0.01,null,'porcentaje','2012-05-07','','LRPVH art. 31'),
('INCES_TRABAJADOR','Aporte INCES del trabajador sobre utilidades',0.005,null,'porcentaje','2014-11-19','','Ley INCES art. 14 num. 2'),

-- Alícuotas patronales
('IVSS_PATRONO_RIESGO_MINIMO','Aporte patronal IVSS riesgo mínimo',0.09,null,'porcentaje','2012-05-07','','Ley del Seguro Social art. 62'),
('IVSS_PATRONO_RIESGO_MEDIO','Aporte patronal IVSS riesgo medio',0.10,null,'porcentaje','2012-05-07','','Ley del Seguro Social art. 62'),
('IVSS_PATRONO_RIESGO_ALTO','Aporte patronal IVSS riesgo elevado',0.11,null,'porcentaje','2012-05-07','','Ley del Seguro Social art. 62'),
('RPE_PATRONO','Aporte patronal Régimen Prestacional de Empleo',0.02,null,'porcentaje','2012-05-07','','LRPE art. 46'),
('FAOV_PATRONO','Aporte patronal FAOV',0.02,null,'porcentaje','2012-05-07','','LRPVH art. 31'),
('INCES_PATRONO','Aporte patronal INCES sobre salarios normales',0.02,null,'porcentaje','2014-11-19','','Ley INCES art. 14 num. 1'),

-- Topes y factores
('TOPE_SM_IVSS','Tope de cotización IVSS en salarios mínimos',5,null,'factor','2012-05-07','','Ley del Seguro Social'),
('RECARGO_HE_DIURNA','Recargo de hora extra diurna',0.50,null,'porcentaje','2012-05-07','','LOTTT art. 118'),
('RECARGO_NOCTURNO','Bono nocturno',0.30,null,'porcentaje','2012-05-07','','LOTTT art. 117'),
('RECARGO_FERIADO','Recargo por día feriado o descanso trabajado',0.50,null,'porcentaje','2012-05-07','','LOTTT art. 120'),
('TOPE_HE_DIARIAS','Máximo de horas extra por día',2,null,'dias','2012-05-07','','LOTTT art. 178'),
('TOPE_HE_SEMANALES','Máximo de horas extra por semana',10,null,'dias','2012-05-07','','LOTTT art. 178'),
('TOPE_HE_ANUALES','Máximo de horas extra por año',100,null,'dias','2012-05-07','','LOTTT art. 178'),
('TOPE_ANTICIPO_PRESTACIONES','Anticipo máximo sobre prestaciones',0.75,null,'porcentaje','2012-05-07','','LOTTT art. 144'),
('ISLR_UT_MINIMO_ANUAL','Enriquecimiento anual mínimo gravable en U.T.',1000,null,'factor','2012-05-07','','LISLR art. 79'),
('TASA_ACTIVA_BCV','Tasa activa promedio BCV para intereses de prestaciones',0.5900,null,'porcentaje','2026-01-01','','LOTTT art. 143 lit. c');

-- ---------------------------------------------------------------------
-- TRAMOS ISLR (tarifa Nº 1 - personas naturales, expresada en U.T.)
-- ---------------------------------------------------------------------
insert into islr_tramos (desde_ut, hasta_ut, porcentaje, sustraendo_ut, vigente_desde) values
(0,      1000,  6.00,   0,    '2012-01-01'),
(1000,   1500,  9.00,   30,   '2012-01-01'),
(1500,   2000, 12.00,   75,   '2012-01-01'),
(2000,   2500, 16.00,  155,   '2012-01-01'),
(2500,   3000, 20.00,  255,   '2012-01-01'),
(3000,   4000, 24.00,  375,   '2012-01-01'),
(4000,   6000, 29.00,  575,   '2012-01-01'),
(6000,   null, 34.00,  875,   '2012-01-01');

-- ---------------------------------------------------------------------
-- CONCEPTOS DE NÓMINA
-- ---------------------------------------------------------------------
insert into conceptos_nomina
 (empresa_id, codigo, nombre, caracter, base, factor, moneda,
  incide_prestaciones, incide_vacaciones, incide_utilidades, incide_islr, orden, fundamento_legal)
values
-- ASIGNACIONES SALARIALES
('11111111-1111-1111-1111-111111111111','101','Salario base','salarial','salario_diario_normal',1,'VES',true,true,true,true,10,'LOTTT art. 104'),
('11111111-1111-1111-1111-111111111111','102','Día de descanso','salarial','salario_diario_normal',1,'VES',true,true,true,true,15,'LOTTT art. 119'),
('11111111-1111-1111-1111-111111111111','103','Día feriado','salarial','salario_diario_normal',1,'VES',true,true,true,true,16,'LOTTT art. 120'),
('11111111-1111-1111-1111-111111111111','110','Horas extra diurnas','salarial','formula',1.5,'VES',true,true,true,true,20,'LOTTT art. 118'),
('11111111-1111-1111-1111-111111111111','111','Horas extra nocturnas','salarial','formula',1.95,'VES',true,true,true,true,21,'LOTTT art. 117-118'),
('11111111-1111-1111-1111-111111111111','112','Feriado trabajado','salarial','formula',1.5,'VES',true,true,true,true,22,'LOTTT art. 120'),
('11111111-1111-1111-1111-111111111111','113','Bono nocturno','salarial','formula',0.3,'VES',true,true,true,true,23,'LOTTT art. 117'),
('11111111-1111-1111-1111-111111111111','120','Prima de antigüedad','salarial','monto_fijo',1,'VES',true,true,true,true,30,'Convención colectiva'),
('11111111-1111-1111-1111-111111111111','121','Comisiones por venta','salarial','monto_fijo',1,'VES',true,true,true,true,31,'LOTTT art. 104'),
('11111111-1111-1111-1111-111111111111','130','Bono vacacional','salarial','salario_diario_normal',1,'VES',false,false,true,true,40,'LOTTT art. 192'),
('11111111-1111-1111-1111-111111111111','131','Vacaciones (disfrute)','salarial','salario_diario_normal',1,'VES',false,false,true,true,41,'LOTTT art. 190'),
('11111111-1111-1111-1111-111111111111','140','Utilidades','salarial','salario_diario_normal',1,'VES',false,false,false,true,45,'LOTTT art. 131'),

-- ASIGNACIONES NO SALARIALES
('11111111-1111-1111-1111-111111111111','201','Cestaticket socialista','no_salarial','monto_fijo',1,'USD',false,false,false,false,50,'Ley de Alimentación art. 5'),
('11111111-1111-1111-1111-111111111111','202','Bono de guerra económica','no_salarial','monto_fijo',1,'USD',false,false,false,false,51,'LOTTT art. 105'),
('11111111-1111-1111-1111-111111111111','203','Bonificación extraordinaria','no_salarial','monto_fijo',1,'USD',false,false,false,false,52,'LOTTT art. 105'),

-- DEDUCCIONES
('11111111-1111-1111-1111-111111111111','301','IVSS (4%)','deduccion','formula',0.04,'VES',false,false,false,false,60,'Ley del Seguro Social art. 62'),
('11111111-1111-1111-1111-111111111111','302','RPE Paro Forzoso (0,5%)','deduccion','formula',0.005,'VES',false,false,false,false,61,'LRPE art. 46'),
('11111111-1111-1111-1111-111111111111','303','FAOV (1%)','deduccion','formula',0.01,'VES',false,false,false,false,62,'LRPVH art. 31'),
('11111111-1111-1111-1111-111111111111','304','INCES (0,5% s/utilidades)','deduccion','formula',0.005,'VES',false,false,false,false,63,'Ley INCES art. 14'),
('11111111-1111-1111-1111-111111111111','305','Retención ISLR','deduccion','formula',1,'VES',false,false,false,false,64,'LISLR / Decreto 1.808'),
('11111111-1111-1111-1111-111111111111','310','Préstamo personal','deduccion','monto_fijo',1,'VES',false,false,false,false,70,'Autorización del trabajador'),
('11111111-1111-1111-1111-111111111111','311','Anticipo de prestaciones','deduccion','monto_fijo',1,'VES',false,false,false,false,71,'LOTTT art. 144'),
('11111111-1111-1111-1111-111111111111','312','Caja de ahorros','deduccion','monto_fijo',1,'VES',false,false,false,false,72,'Reglamento interno'),
('11111111-1111-1111-1111-111111111111','313','Inasistencia injustificada','deduccion','salario_diario_normal',1,'VES',false,false,false,false,73,'LOTTT art. 79 lit. f'),

-- APORTES PATRONALES (no aparecen en el recibo del trabajador)
('11111111-1111-1111-1111-111111111111','401','IVSS patronal','aporte_patronal','formula',0.10,'VES',false,false,false,false,80,'Ley del Seguro Social art. 62'),
('11111111-1111-1111-1111-111111111111','402','RPE patronal','aporte_patronal','formula',0.02,'VES',false,false,false,false,81,'LRPE art. 46'),
('11111111-1111-1111-1111-111111111111','403','FAOV patronal','aporte_patronal','formula',0.02,'VES',false,false,false,false,82,'LRPVH art. 31'),
('11111111-1111-1111-1111-111111111111','404','INCES patronal','aporte_patronal','formula',0.02,'VES',false,false,false,false,83,'Ley INCES art. 14');

update conceptos_nomina set imprime_en_recibo = false where caracter = 'aporte_patronal';

-- ---------------------------------------------------------------------
-- FERIADOS NACIONALES 2026 (art. 184 LOTTT)
-- ---------------------------------------------------------------------
insert into feriados (fecha, nombre, tipo) values
('2026-01-01','Año Nuevo','nacional'),
('2026-02-16','Lunes de Carnaval','nacional'),
('2026-02-17','Martes de Carnaval','nacional'),
('2026-04-02','Jueves Santo','nacional'),
('2026-04-03','Viernes Santo','nacional'),
('2026-04-19','Declaración de la Independencia','nacional'),
('2026-05-01','Día del Trabajador','nacional'),
('2026-06-24','Batalla de Carabobo','nacional'),
('2026-07-05','Día de la Independencia','nacional'),
('2026-07-24','Natalicio del Libertador','nacional'),
('2026-10-12','Día de la Resistencia Indígena','nacional'),
('2026-12-24','Nochebuena','convencional'),
('2026-12-25','Navidad','nacional'),
('2026-12-31','Fin de Año','convencional');

-- ---------------------------------------------------------------------
-- HORARIOS TIPO DE RETAIL
-- ---------------------------------------------------------------------
insert into horarios (id, empresa_id, nombre, tipo_jornada, horas_diarias, horas_semanales) values
('22222222-2222-2222-2222-222222222221','11111111-1111-1111-1111-111111111111','Tienda turno completo','especial_comercio',8,40),
('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','Tienda turno tarde','especial_comercio',8,40);

insert into horario_dias (horario_id, dia_semana, hora_entrada, hora_salida, inicio_almuerzo, fin_almuerzo, es_descanso) values
('22222222-2222-2222-2222-222222222221',1,'09:00','17:00','13:00','14:00',false),
('22222222-2222-2222-2222-222222222221',2,'09:00','17:00','13:00','14:00',false),
('22222222-2222-2222-2222-222222222221',3,'09:00','17:00','13:00','14:00',false),
('22222222-2222-2222-2222-222222222221',4,'09:00','17:00','13:00','14:00',false),
('22222222-2222-2222-2222-222222222221',5,'09:00','17:00','13:00','14:00',false),
('22222222-2222-2222-2222-222222222221',6,'10:00','18:00','14:00','15:00',false),
('22222222-2222-2222-2222-222222222221',0,null,null,null,null,true),
('22222222-2222-2222-2222-222222222222',1,'12:00','20:00','16:00','17:00',false),
('22222222-2222-2222-2222-222222222222',2,'12:00','20:00','16:00','17:00',false),
('22222222-2222-2222-2222-222222222222',3,'12:00','20:00','16:00','17:00',false),
('22222222-2222-2222-2222-222222222222',4,'12:00','20:00','16:00','17:00',false),
('22222222-2222-2222-2222-222222222222',5,'12:00','20:00','16:00','17:00',false),
('22222222-2222-2222-2222-222222222222',6,'12:00','20:00','16:00','17:00',false),
('22222222-2222-2222-2222-222222222222',0,null,null,null,null,true);

-- ---------------------------------------------------------------------
-- CARGOS
-- ---------------------------------------------------------------------
insert into cargos (empresa_id, nombre, departamento, es_de_direccion) values
('11111111-1111-1111-1111-111111111111','Gerente General','Dirección',true),
('11111111-1111-1111-1111-111111111111','Supervisor de Tienda','Operaciones',false),
('11111111-1111-1111-1111-111111111111','Supervisor Auxiliar','Operaciones',false),
('11111111-1111-1111-1111-111111111111','Vendedor','Piso de Venta',false),
('11111111-1111-1111-1111-111111111111','Cajero','Piso de Venta',false),
('11111111-1111-1111-1111-111111111111','Almacenista','Almacén',false),
('11111111-1111-1111-1111-111111111111','Visual Merchandiser','Piso de Venta',false),
('11111111-1111-1111-1111-111111111111','Analista de Nómina','Recursos Humanos',false);

-- ---------------------------------------------------------------------
-- TASA BCV INICIAL (la Edge Function la actualiza a diario)
-- ---------------------------------------------------------------------
-- Serie histórica mínima. En producción la Edge Function sync-bcv inserta
-- una fila por día hábil; sin la tasa del día el cálculo se detiene por diseño.
insert into tasas_cambio (fecha, tasa_usd, origen) values
('2021-01-01',   1.80000000,'manual'),
('2022-01-01',   4.60000000,'manual'),
('2023-01-01',  17.50000000,'manual'),
('2024-01-01',  35.90000000,'manual'),
('2025-01-01',  52.00000000,'manual'),
('2026-01-01', 190.00000000,'manual'),
('2026-06-01', 235.00000000,'manual')
on conflict (fecha) do nothing;

insert into tasas_cambio (fecha, tasa_usd, origen)
values (current_date, 250.00000000, 'manual')
on conflict (fecha) do nothing;
